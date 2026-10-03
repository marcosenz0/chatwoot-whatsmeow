require 'rails_helper'

RSpec.describe Whatsmeow::IncomingMessageService do
  subject(:service) { described_class.new(inbox: inbox, params: params) }

  let(:inbox) { instance_double(Inbox) }

  let(:params) do
    {
      timestamp: 1_700_000_000,
      pix: {
        key_type: 'EMAIL',
        key: 'PAYMENTS@EXAMPLE.COM',
        merchant_name: 'Example Store'
      }
    }.with_indifferent_access
  end

  it 'keeps native Pix data in message content attributes' do
    expect(service.send(:message_content_attributes)).to include(
      whatsmeow_pix: {
        key_type: 'EMAIL',
        key: 'payments@example.com',
        merchant_name: 'Example Store'
      }
    )
  end

  it 'uses the merchant name as searchable fallback content' do
    expect(service.send(:message_content)).to eq('Example Store')
  end

  it 'preserves view once and disappearing message markers' do
    params.merge!(view_once: true, view_once_unavailable: true, ephemeral: true)
    expect(service.send(:message_content_attributes)).to include(
      whatsmeow_view_once: true, whatsmeow_view_once_unavailable: true, whatsmeow_ephemeral: true
    )
  end

  it 'uses a localized notice when WhatsApp did not supply view once media' do
    params.merge!(view_once: true, view_once_unavailable: true, content: 'View once message.')
    allow(inbox).to receive(:account).and_return(instance_double(Account, locale: 'pt_BR'))
    expect(service.send(:message_content)).to eq(I18n.t('messages.whatsmeow_view_once_unavailable', locale: 'pt_BR'))
  end

  it 'preserves supplied content when view once media is available' do
    params.merge!(view_once: true, view_once_unavailable: false, content: 'Supplied caption')
    expect(service.send(:message_content)).to eq('Supplied caption')
  end

  context 'when a received Pix key does not match local validation rules' do
    let(:params) do
      {
        timestamp: 1_700_000_000,
        pix: { key_type: 'EMAIL', key: 'invalid', merchant_name: 'Example Store' }
      }.with_indifferent_access
    end

    it 'preserves the received card without failing message processing' do
      expect(service.send(:message_content_attributes)).to include(
        whatsmeow_pix: { key_type: 'EMAIL', key: 'invalid', merchant_name: 'Example Store' }
      )
    end
  end
end
