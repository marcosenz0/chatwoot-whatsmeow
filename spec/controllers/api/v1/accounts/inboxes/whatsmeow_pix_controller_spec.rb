require 'rails_helper'

RSpec.describe 'Whatsmeow Pix configuration API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:channel) { create(:channel_whatsmeow, account: account) }
  let(:inbox) { channel.inbox }
  let(:endpoint) { "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/whatsmeow_pix" }

  before do
    create(:inbox_member, inbox: inbox, user: agent)
  end

  describe 'GET /api/v1/accounts/:account_id/inboxes/:inbox_id/whatsmeow_pix' do
    it 'allows an account administrator without direct inbox membership' do
      get endpoint, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('configured' => false, 'can_manage' => true)
    end

    it 'returns the configuration to an assigned agent without management permission' do
      channel.update!(pix_key_type: 'EMAIL', pix_key: 'payments@example.com', pix_merchant_name: 'Example Store')

      get endpoint, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq(
        'configured' => true,
        'can_manage' => false,
        'pix' => {
          'key_type' => 'EMAIL',
          'key' => 'payments@example.com',
          'merchant_name' => 'Example Store'
        }
      )
    end

    it 'allows an AgentBot token linked to this inbox to inspect the configuration' do
      bot = create(:agent_bot, account: account)
      create(:agent_bot_inbox, inbox: inbox, agent_bot: bot)

      get endpoint, headers: { api_access_token: bot.access_token.token }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('configured' => false, 'can_manage' => false)
    end

    it 'allows a team member of the conversation to inspect its Pix configuration' do
      team = create(:team, account: account)
      conversation = create(:conversation, :with_team, account: account, inbox: inbox, team: team)
      team_agent = create(:user, account: account, role: :agent)
      create(:team_member, team: team, user: team_agent)

      get endpoint,
          params: { conversation_id: conversation.display_id },
          headers: team_agent.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('configured' => false, 'can_manage' => false)
    end
  end

  describe 'PATCH /api/v1/accounts/:account_id/inboxes/:inbox_id/whatsmeow_pix' do
    it 'normalizes and stores the configuration for an administrator' do
      patch endpoint,
            params: { key_type: 'phone', key: '(63) 99264-5568', merchant_name: 'Example Store' },
            headers: admin.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('pix', 'key')).to eq('+5563992645568')
      expect(channel.reload).to have_attributes(
        pix_key_type: 'PHONE',
        pix_key: '+5563992645568',
        pix_merchant_name: 'Example Store'
      )
    end

    it 'rejects an invalid key with a machine-readable code' do
      patch endpoint,
            params: { key_type: 'EVP', key: 'invalid', merchant_name: 'Example Store' },
            headers: admin.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.dig('error', 'code')).to eq('invalid_pix_payload')
    end

    it 'does not let an agent change the shared inbox key' do
      patch endpoint,
            params: { key_type: 'EMAIL', key: 'payments@example.com', merchant_name: 'Example Store' },
            headers: agent.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'DELETE /api/v1/accounts/:account_id/inboxes/:inbox_id/whatsmeow_pix' do
    it 'removes the configuration' do
      channel.update!(pix_key_type: 'EMAIL', pix_key: 'payments@example.com', pix_merchant_name: 'Example Store')

      delete endpoint, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('configured' => false, 'pix' => nil)
      expect(channel.reload).to have_attributes(pix_key_type: nil, pix_key: nil, pix_merchant_name: nil)
    end
  end
end
