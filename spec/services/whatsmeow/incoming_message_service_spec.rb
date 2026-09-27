require 'rails_helper'

RSpec.describe Whatsmeow::IncomingMessageService do
  subject(:service) { described_class.new(inbox: instance_double(Inbox), params: params) }

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
