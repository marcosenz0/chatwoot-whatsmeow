require 'rails_helper'

describe Whatsapp::CloudTemplateService do
  subject(:service) { described_class.new(inbox: inbox) }

  let(:channel) do
    create(
      :channel_whatsapp,
      provider: 'whatsapp_cloud',
      validate_provider_config: false,
      sync_templates: false
    )
  end
  let(:inbox) { channel.inbox }
  let(:template_attributes) do
    {
      name: 'Order Update',
      language: 'pt_BR',
      category: 'utility',
      components: [
        {
          type: 'body',
          text: 'Hello {{1}}, your order is ready.',
          example: { body_text: [['Marcos']] }
        },
        {
          type: 'buttons',
          buttons: [{ type: 'quick_reply', text: 'View order' }]
        }
      ]
    }
  end

  before do
    stub_request(
      :get,
      'https://graph.facebook.com/v22.0/123456789/message_templates'
    ).to_return(
      status: 200,
      body: { data: [{ name: 'order_update', status: 'PENDING' }] }.to_json,
      headers: { 'Content-Type' => 'application/json' }
    )
  end

  it 'submits a sanitized template to the connected WABA and syncs the cache' do
    request = stub_request(
      :post,
      'https://graph.facebook.com/v22.0/123456789/message_templates'
    ).with(
      headers: { 'Authorization' => 'Bearer test_key' },
      body: {
        name: 'order_update',
        language: 'pt_BR',
        category: 'UTILITY',
        allow_category_change: true,
        components: [
          {
            type: 'BODY',
            text: 'Hello {{1}}, your order is ready.',
            example: { body_text: [['Marcos']] }
          },
          {
            type: 'BUTTONS',
            buttons: [{ type: 'QUICK_REPLY', text: 'View order' }]
          }
        ]
      }.to_json
    ).to_return(
      status: 200,
      body: { id: 'template-id', status: 'PENDING' }.to_json,
      headers: { 'Content-Type' => 'application/json' }
    )

    expect(service.create!(template_attributes)).to include('id' => 'template-id')
    expect(request).to have_been_requested.once
    expect(channel.reload.message_templates).to contain_exactly(
      include('name' => 'order_update', 'status' => 'PENDING')
    )
  end

  context 'with a Whatsmeow inbox' do
    let(:inbox) { create(:channel_whatsmeow).inbox }

    it 'refuses to call the Cloud API' do
      expect { service.create!(template_attributes) }
        .to raise_error(described_class::Error, 'Official WhatsApp Cloud API inbox required')
    end
  end
end
