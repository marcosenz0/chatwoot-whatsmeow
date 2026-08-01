require 'rails_helper'

describe WhatsappAutomation do
  let(:account) { create(:account) }
  let(:channel) do
    create(
      :channel_whatsapp,
      account: account,
      provider: 'whatsapp_cloud',
      sync_templates: false,
      validate_provider_config: false
    )
  end
  let(:automation) do
    described_class.create!(
      account: account,
      inbox: channel.inbox,
      name: 'Order updates',
      trigger_type: 'keyword',
      trigger_config: { 'keywords' => ['order'] },
      definition: definition
    )
  end
  let(:definition) do
    {
      'nodes' => [
        { 'id' => 'trigger', 'type' => 'trigger', 'config' => {} },
        {
          'id' => 'message',
          'type' => 'message',
          'config' => {
            'mode' => 'session',
            'text' => 'How can we help?',
            'buttons' => []
          }
        },
        { 'id' => 'end', 'type' => 'end', 'config' => {} }
      ],
      'edges' => [
        { 'id' => 'edge-1', 'source' => 'trigger', 'target' => 'message', 'source_handle' => 'default' },
        { 'id' => 'edge-2', 'source' => 'message', 'target' => 'end', 'source_handle' => 'default' }
      ]
    }
  end

  describe '#publish!' do
    it 'saves incomplete content as a draft but rejects it when publishing' do
      definition['nodes'][1]['config']['text'] = ''

      expect { automation }.not_to raise_error
      expect { automation.publish! }
        .to raise_error(ActiveRecord::RecordInvalid, /needs text/)
    end

    it 'requires at least one keyword for keyword automations' do
      automation.trigger_config = { 'keywords' => [] }

      expect { automation.publish! }
        .to raise_error(ActiveRecord::RecordInvalid, /at least one keyword/)
    end

    it 'requires template nodes to match an approved synchronized template' do
      definition['nodes'][1]['config'] = {
        'mode' => 'template',
        'template_name' => 'order_update',
        'language' => 'pt_BR',
        'preview_text' => 'Order ready',
        'buttons' => [],
        'processed_params' => {}
      }

      expect { automation.publish! }
        .to raise_error(ActiveRecord::RecordInvalid, /synchronized template/)

      channel.update!(message_templates: [
                        {
                          'name' => 'order_update',
                          'language' => 'pt_BR',
                          'status' => 'APPROVED',
                          'category' => 'UTILITY',
                          'components' => [{ 'type' => 'BODY', 'text' => 'Order ready' }]
                        }
                      ])

      expect { automation.publish! }.to change(automation, :status).from('draft').to('active')
    end

    it 'requires media, named text, and dynamic button parameters before publishing' do
      definition['nodes'][1]['config'] = {
        'mode' => 'template',
        'template_name' => 'order_update',
        'language' => 'pt_BR',
        'preview_text' => 'Olá {{customer_name}}',
        'buttons' => [],
        'processed_params' => {
          'header' => { 'media_type' => 'image', 'media_url' => '' },
          'body' => { 'customer_name' => 'Marcos' },
          'buttons' => [
            { 'type' => 'url', 'index' => 0, 'parameter' => '' },
            { 'type' => 'copy_code', 'index' => 1, 'parameter' => 'DESCONTO10' }
          ]
        }
      }
      channel.update!(message_templates: [
                        {
                          'name' => 'order_update',
                          'language' => 'pt_BR',
                          'status' => 'APPROVED',
                          'category' => 'UTILITY',
                          'parameter_format' => 'NAMED',
                          'components' => [
                            { 'type' => 'HEADER', 'format' => 'IMAGE' },
                            { 'type' => 'BODY', 'text' => 'Olá {{customer_name}}' },
                            {
                              'type' => 'BUTTONS',
                              'buttons' => [
                                { 'type' => 'URL', 'text' => 'Pedido', 'url' => 'https://example.com/{{order_id}}' },
                                { 'type' => 'COPY_CODE', 'text' => 'Copiar código' }
                              ]
                            }
                          ]
                        }
                      ])

      expect { automation.publish! }
        .to raise_error(ActiveRecord::RecordInvalid, /valid header media URL.*button parameters 0/m)

      definition['nodes'][1]['config']['processed_params']['header']['media_url'] = 'https://example.com/order.png'
      definition['nodes'][1]['config']['processed_params']['buttons'][0]['parameter'] = '123'
      automation.update!(definition: definition)

      expect { automation.publish! }.to change(automation, :status).from('draft').to('active')
    end

    it 'rejects authentication templates from the journey editor' do
      definition['nodes'][1]['config'] = {
        'mode' => 'template',
        'template_name' => 'login_code',
        'language' => 'pt_BR',
        'preview_text' => 'Seu código',
        'buttons' => [],
        'processed_params' => {}
      }
      channel.update!(message_templates: [
                        {
                          'name' => 'login_code',
                          'language' => 'pt_BR',
                          'status' => 'APPROVED',
                          'category' => 'AUTHENTICATION',
                          'components' => [{ 'type' => 'BODY', 'text' => 'Seu código' }]
                        }
                      ])

      expect { automation.publish! }
        .to raise_error(ActiveRecord::RecordInvalid, /unsupported template components/)
    end
  end

  it 'returns an active automation to draft and cancels unfinished runs when its definition changes' do
    automation.publish!
    run = WhatsappAutomationRun.create!(
      account: account,
      whatsapp_automation: automation,
      contact: create(:contact, account: account),
      status: :waiting_reply,
      current_node_id: 'message'
    )
    changed_definition = automation.definition.deep_dup
    changed_definition['nodes'][1]['config']['text'] = 'Updated response'

    automation.update!(definition: changed_definition)

    expect(automation).to be_draft
    expect(automation.published_at).to be_nil
    expect(run.reload).to be_cancelled
  end

  it 'cancels unfinished runs when paused' do
    automation.publish!
    run = WhatsappAutomationRun.create!(
      account: account,
      whatsapp_automation: automation,
      contact: create(:contact, account: account),
      status: :waiting,
      current_node_id: 'message',
      next_run_at: 1.hour.from_now
    )

    automation.pause!

    expect(automation).to be_paused
    expect(run.reload).to be_cancelled
    expect(run.next_run_at).to be_nil
  end
end
