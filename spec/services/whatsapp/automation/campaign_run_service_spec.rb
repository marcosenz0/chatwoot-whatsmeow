require 'rails_helper'

describe Whatsapp::Automation::CampaignRunService do
  let(:account) { create(:account) }
  let(:channel) do
    create(
      :channel_whatsapp,
      account: account,
      provider: 'whatsapp_cloud',
      validate_provider_config: false,
      sync_templates: false
    )
  end
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, :with_phone_number, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:buttons) do
    [
      { 'id' => 'template_reply_0', 'title' => 'Pode mandar exemplos' },
      { 'id' => 'template_reply_1', 'title' => 'Agora não, obrigado' }
    ]
  end
  let(:automation) do
    WhatsappAutomation.create!(
      account: account,
      inbox: inbox,
      name: 'Pós-disparo',
      trigger_type: 'campaign_reply',
      trigger_config: { template_name: 'examples', language: 'pt_BR' },
      definition: {
        'nodes' => [
          { 'id' => 'trigger', 'type' => 'trigger', 'config' => { 'buttons' => buttons } },
          { 'id' => 'message', 'type' => 'message', 'config' => { 'mode' => 'session', 'text' => 'Resposta' } },
          { 'id' => 'end', 'type' => 'end', 'config' => {} }
        ],
        'edges' => buttons.map.with_index do |button, index|
          {
            'id' => "edge-#{index}",
            'source' => 'trigger',
            'target' => index.zero? ? 'message' : 'end',
            'source_handle' => button['id']
          }
        end + [{ 'id' => 'edge-message', 'source' => 'message', 'target' => 'end', 'source_handle' => 'default' }]
      },
      status: :active,
      published_at: Time.current
    )
  end
  let(:campaign) do
    create(
      :campaign,
      account: account,
      inbox: inbox,
      trigger_rules: { whatsapp_automation_id: automation.id },
      template_params: { 'name' => 'examples', 'language' => 'pt_BR' }
    )
  end
  let(:message) do
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing)
  end

  it 'creates a reply-waiting run tied to the campaign message' do
    expect do
      described_class.new(campaign: campaign, contact: contact, conversation: conversation, message: message).perform
    end.to change(WhatsappAutomationRun, :count).by(1)

    run = automation.runs.last
    expect(run).to have_attributes(status: 'waiting_reply', current_node_id: 'trigger', conversation: conversation)
    expect(run.context).to include(
      'campaign_id' => campaign.id,
      'last_outgoing_message_id' => message.id,
      'expected_buttons' => buttons
    )
  end
end
