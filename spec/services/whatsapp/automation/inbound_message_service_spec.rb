require 'rails_helper'

describe Whatsapp::Automation::InboundMessageService do
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
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: account, phone_number: '+15551234567') }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: '15551234567') }
  let(:conversation) do
    create(
      :conversation,
      account: account,
      inbox: inbox,
      contact: contact,
      contact_inbox: contact_inbox
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
            'text' => 'Continue?',
            'buttons' => [{ 'id' => 'yes', 'title' => 'Sim' }]
          }
        },
        { 'id' => 'end', 'type' => 'end', 'config' => {} }
      ],
      'edges' => [
        { 'id' => 'trigger-edge', 'source' => 'trigger', 'target' => 'message', 'source_handle' => 'default' },
        { 'id' => 'button-edge', 'source' => 'message', 'target' => 'end', 'source_handle' => 'yes' }
      ]
    }
  end
  let(:first_automation) do
    WhatsappAutomation.create!(
      account: account,
      inbox: inbox,
      name: 'First flow',
      trigger_type: 'any_message',
      definition: definition,
      status: :active,
      published_at: Time.current
    )
  end
  let(:second_automation) do
    WhatsappAutomation.create!(
      account: account,
      inbox: inbox,
      name: 'Second flow',
      trigger_type: 'any_message',
      definition: definition,
      status: :active,
      published_at: Time.current
    )
  end
  let(:first_outgoing) do
    create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      message_type: :outgoing,
      source_id: 'wamid.first-flow'
    )
  end
  let(:second_outgoing) do
    create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      message_type: :outgoing,
      source_id: 'wamid.second-flow'
    )
  end
  let!(:first_run) { create_waiting_run(first_automation, first_outgoing) }
  let!(:second_run) { create_waiting_run(second_automation, second_outgoing) }

  it 'uses the reply context to advance only the run for the selected message' do
    reply = create_reply(in_reply_to: second_outgoing.id)

    expect { described_class.new(message: reply).perform }
      .to have_enqueued_job(Whatsapp::Automation::RunJob).with(second_run.id).exactly(:once)

    expect(first_run.reload).to be_waiting_reply
    expect(second_run.reload).to be_running
    expect(second_run.current_node_id).to eq('end')
    expect(second_run.context).to include(
      'last_button_id' => 'yes',
      'last_reply_message_id' => reply.id
    )
  end

  it 'uses the external source id when only the provider reply context is available' do
    reply = create_reply
    reply.content_attributes = reply.content_attributes.except('in_reply_to').merge(
      'in_reply_to_external_id' => first_outgoing.source_id
    )

    expect { described_class.new(message: reply).perform }
      .to have_enqueued_job(Whatsapp::Automation::RunJob).with(first_run.id).exactly(:once)

    expect(first_run.reload).to be_running
    expect(second_run.reload).to be_waiting_reply
  end

  it 'does not advance multiple runs when an unscoped text reply matches the same button' do
    reply = create_reply

    expect { described_class.new(message: reply).perform }
      .not_to have_enqueued_job(Whatsapp::Automation::RunJob)

    expect(first_run.reload).to be_waiting_reply
    expect(second_run.reload).to be_waiting_reply
  end

  it 'accepts a button reply that arrives before the run enters waiting reply' do
    first_run.update!(
      status: :running,
      context: {
        'last_outgoing_message_id' => first_outgoing.id,
        'awaiting_message_id' => first_outgoing.id,
        'awaiting_node_id' => 'message'
      }
    )
    reply = create_reply(in_reply_to: first_outgoing.id)

    expect { described_class.new(message: reply).perform }
      .to have_enqueued_job(Whatsapp::Automation::RunJob).with(first_run.id).exactly(:once)

    expect(first_run.reload).to be_running
    expect(first_run.current_node_id).to eq('end')
    expect(first_run.context).not_to include('awaiting_message_id', 'awaiting_node_id')
    expect(first_run.context).to include(
      'last_button_id' => 'yes',
      'last_reply_message_id' => reply.id
    )
    expect(second_run.reload).to be_waiting_reply
  end

  def create_waiting_run(automation, outgoing_message)
    WhatsappAutomationRun.create!(
      account: account,
      whatsapp_automation: automation,
      contact: contact,
      conversation: conversation,
      status: :waiting_reply,
      current_node_id: 'message',
      context: {
        'last_outgoing_message_id' => outgoing_message.id,
        'expected_buttons' => [{ 'id' => 'yes', 'title' => 'Sim' }]
      }
    )
  end

  def create_reply(in_reply_to: nil)
    create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      sender: contact,
      message_type: :incoming,
      content: 'Sim',
      content_attributes: {
        in_reply_to: in_reply_to,
        whatsapp_interactive_reply: {
          type: 'button',
          id: 'yes',
          title: 'Sim'
        }
      }.compact
    )
  end
end
