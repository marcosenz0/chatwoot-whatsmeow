# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Devise::Mailer' do
  describe 'confirmation_instructions with Enterprise features' do
    let(:account) { create(:account) }
    let!(:confirmable_user) { create(:user, inviter: inviter_val, account: account) }
    let(:inviter_val) { nil }
    let(:mail) { Devise::Mailer.confirmation_instructions(confirmable_user.reload, nil, {}) }
    let(:mail_body) { CGI.unescapeHTML(mail.body.decoded) }

    before do
      confirmable_user.update!(confirmed_at: nil)
      confirmable_user.send(:generate_confirmation_token)
    end

    context 'when brand name is intentionally blank' do
      before do
        create(:installation_config, name: 'BRAND_NAME', value: '')
      end

      it 'preserves the blank brand override' do
        expect(mail_body).not_to include('Chatwoot')
      end
    end

    context 'with SAML enabled account' do
      let(:saml_settings) { create(:account_saml_settings, account: account) }

      before { saml_settings }

      context 'when user has no inviter' do
        it 'shows standard welcome message without SSO references' do
          expect(mail_body).to include('Confirme seu e-mail para começar')
          expect(mail_body).to include('Precisamos verificar seu endereço de e-mail antes de você começar a usar sua conta.')
          expect(mail_body).not_to include('Single Sign-On (SSO)')
        end

        it 'shows the standard confirmation CTA' do
          expect(mail_body).to include('Confirmar minha conta')
        end

        it 'shows confirmation link' do
          expect(mail.body).to include("app/auth/confirmation?confirmation_token=#{confirmable_user.confirmation_token}")
        end
      end

      context 'when user has inviter and SAML is enabled' do
        let(:inviter_val) { create(:user, :administrator, skip_confirmation: true, account: account) }

        it 'mentions SSO invitation' do
          expect(mail_body).to include("Você foi convidado para participar de #{account.name}")
          expect(mail_body).to include("#{inviter_val.name} convidou você para acessar o espaço #{account.name} no Chatwoot.")
        end

        it 'explains SSO authentication' do
          expect(mail_body).to include('Sua organização usa Single Sign-On (SSO), então você não precisa criar uma senha separada.')
        end

        it 'does not show standard invitation message' do
          expect(mail_body).not_to include('convidou você para participar')
          expect(mail_body).not_to include('Aceitar convite')
        end

        it 'directs to SSO portal instead of password reset' do
          expect(mail_body).to include('Use o portal SSO da sua organização')
          expect(mail.body).not_to include('app/auth/password/edit')
        end
      end

      context 'when user is already confirmed and has inviter' do
        let(:inviter_val) { create(:user, :administrator, skip_confirmation: true, account: account) }

        before do
          confirmable_user.confirm
        end

        it 'shows SSO login instructions' do
          expect(mail_body).to include('Seu acesso está pronto')
          expect(mail_body).to include('Entre com o SSO da sua organização')
          expect(mail_body).to include('Use o portal de Single Sign-On (SSO) da sua organização para acessar')
          expect(mail.body).not_to include('/auth/sign_in')
        end
      end

      context 'when user updates email on SAML account' do
        let(:inviter_val) { create(:user, :administrator, skip_confirmation: true, account: account) }

        before do
          confirmable_user.update!(email: 'updated@example.com')
        end

        it 'still shows confirmation link for email verification' do
          expect(mail_body).to include('Confirme seu novo endereço de e-mail')
          expect(mail.body).to include('app/auth/confirmation?confirmation_token')
          expect(confirmable_user.unconfirmed_email.blank?).to be false
        end
      end

      context 'when user is already confirmed with no inviter' do
        before do
          confirmable_user.confirm
        end

        it 'shows SSO login instructions instead of regular login' do
          expect(mail_body).to include('Seu acesso está pronto')
          expect(mail_body).to include('Entre com o SSO da sua organização')
          expect(mail.body).not_to include('/auth/sign_in')
        end
      end
    end

    context 'when account does not have SAML enabled' do
      context 'when user has inviter' do
        let(:inviter_val) { create(:user, :administrator, skip_confirmation: true, account: account) }

        it 'shows standard invitation without SSO references' do
          expect(mail_body).to include("Você foi convidado para participar de #{account.name}")
          expect(mail_body).to include("#{inviter_val.name} convidou você para participar do espaço #{account.name} no")
          expect(mail_body).not_to include('Single Sign-On (SSO)')
          expect(mail_body).not_to include('Use o portal SSO da sua organização')
        end

        it 'shows password reset link' do
          expect(mail.body).to include('app/auth/password/edit')
        end
      end

      context 'when user has no inviter' do
        it 'shows the standard confirmation state' do
          expect(mail_body).to include('Confirme seu e-mail para começar')
          expect(mail_body).to include('Precisamos verificar seu endereço de e-mail antes de você começar a usar sua conta.')
          expect(mail_body).to include('Confirmar minha conta')
        end

        it 'shows confirmation link' do
          expect(mail.body).to include("app/auth/confirmation?confirmation_token=#{confirmable_user.confirmation_token}")
        end
      end

      context 'when user is already confirmed' do
        let(:inviter_val) { create(:user, :administrator, skip_confirmation: true, account: account) }

        before do
          confirmable_user.confirm
        end

        it 'shows regular login link' do
          expect(mail_body).to include('Sua conta está pronta')
          expect(mail.body).to include('/auth/sign_in')
          expect(mail_body).not_to include('portal SSO')
        end
      end

      context 'when user updates email' do
        before do
          confirmable_user.update!(email: 'updated@example.com')
        end

        it 'shows confirmation link for email verification' do
          expect(mail_body).to include('Confirme seu novo endereço de e-mail')
          expect(mail.body).to include('app/auth/confirmation?confirmation_token')
          expect(confirmable_user.unconfirmed_email.blank?).to be false
        end
      end
    end
  end
end
