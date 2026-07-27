require 'rails_helper'

describe Whatsapp::TemplateProcessorService do
  subject(:components) do
    described_class.new(channel: channel, template_params: template_params, message: nil).call.last
  end

  let(:channel) { instance_double(Channel::Whatsapp, message_templates: [template]) }
  let(:template) do
    {
      'name' => 'interactive_template',
      'language' => 'pt_BR',
      'status' => 'APPROVED'
    }
  end
  let(:template_params) do
    {
      'name' => 'interactive_template',
      'language' => 'pt_BR',
      'processed_params' => {
        'buttons' => [
          { 'type' => 'url', 'index' => 0, 'parameter' => 'order-123' },
          { 'type' => 'quick_reply', 'index' => 2, 'payload' => 'confirm_order' },
          { 'type' => 'copy_code', 'index' => 1, 'parameter' => 'SAVE20' }
        ]
      }
    }
  end

  it 'builds quick reply payloads with explicit indexes while preserving URL and copy-code buttons' do
    expect(components).to eq(
      [
        {
          type: 'button',
          sub_type: 'url',
          index: 0,
          parameters: [{ type: 'text', text: 'order-123' }]
        },
        {
          type: 'button',
          sub_type: 'quick_reply',
          index: 2,
          parameters: [{ type: 'payload', payload: 'confirm_order' }]
        },
        {
          type: 'button',
          sub_type: 'copy_code',
          index: 1,
          parameters: [{ type: 'coupon_code', coupon_code: 'SAVE20' }]
        }
      ]
    )
  end

  context 'with named text-header parameters' do
    let(:template) do
      {
        'name' => 'interactive_template',
        'language' => 'pt_BR',
        'status' => 'APPROVED',
        'parameter_format' => 'NAMED'
      }
    end
    let(:template_params) do
      {
        'name' => 'interactive_template',
        'language' => 'pt_BR',
        'processed_params' => {
          'header' => { 'customer_name' => 'Marcos' }
        }
      }
    end

    it 'preserves the parameter name in the provider payload' do
      expect(components).to eq(
        [
          {
            type: 'header',
            parameters: [
              {
                type: 'text',
                parameter_name: 'customer_name',
                text: 'Marcos'
              }
            ]
          }
        ]
      )
    end
  end
end
