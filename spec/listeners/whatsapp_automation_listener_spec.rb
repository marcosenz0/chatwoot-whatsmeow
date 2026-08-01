require 'rails_helper'

describe WhatsappAutomationListener do
  let(:listener) { described_class.instance }
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
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:message) do
    create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      message_type: :outgoing
    )
  end
  let(:automation) do
    WhatsappAutomation.create!(
      account: account,
      inbox: inbox,
      name: 'Order updates',
      trigger_type: 'any_message',
      definition: {
        'nodes' => [
          {
            'id' => 'message',
            'type' => 'message',
            'config' => {
              'mode' => 'template',
              'template_name' => 'shipping_update',
              'language' => 'pt_BR'
            }
          },
          { 'id' => 'end', 'type' => 'end', 'config' => {} }
        ],
        'edges' => [
          { 'id' => 'edge-1', 'source' => 'message', 'target' => 'end', 'source_handle' => 'default' }
        ]
      }
    )
  end
  let!(:run) do
    WhatsappAutomationRun.create!(
      account: account,
      whatsapp_automation: automation,
      contact: contact,
      conversation: conversation,
      status: :running,
      current_node_id: 'message',
      context: {
        'last_outgoing_message_id' => message.id,
        'awaiting_message_id' => message.id,
        'awaiting_node_id' => 'message'
      }
    )
  end
  let(:event) do
    Events::Base.new(
      'message.updated',
      Time.zone.now,
      message: message,
      previous_changes: previous_changes
    )
  end
  let(:previous_changes) { {} }

  describe '#message_updated' do
    it 'resumes the run when WhatsApp assigns a source id' do
      message.update!(source_id: 'wamid.accepted')

      expect do
        listener.message_updated(event)
      end.to have_enqueued_job(Whatsapp::Automation::RunJob).with(run.id)
    end

    it 'fails the run when the outgoing message fails' do
      message.update!(status: :failed, external_error: 'Meta rejected the message')

      expect do
        listener.message_updated(event)
      end.not_to have_enqueued_job(Whatsapp::Automation::RunJob)

      expect(run.reload).to be_failed
      expect(run.last_error).to eq('Meta rejected the message')
    end

    it 'does not resume while the outgoing message is still pending provider acceptance' do
      expect do
        listener.message_updated(event)
      end.not_to have_enqueued_job(Whatsapp::Automation::RunJob)
    end

    it 'does not resume a run waiting for another message' do
      run.update!(context: run.context.merge('awaiting_message_id' => message.id + 1))
      message.update!(source_id: 'wamid.accepted')

      expect do
        listener.message_updated(event)
      end.not_to have_enqueued_job(Whatsapp::Automation::RunJob)
    end

    it 'fails a reply-waiting run when Meta rejects the accepted button message asynchronously' do
      run.update!(
        status: :waiting_reply,
        context: run.context.except('awaiting_message_id', 'awaiting_node_id').merge(
          'last_outgoing_message_id' => message.id,
          'expected_buttons' => [{ 'id' => 'yes', 'title' => 'Sim' }]
        )
      )
      message.update!(source_id: 'wamid.accepted', status: :failed, external_error: 'Asynchronous delivery failure')

      listener.message_updated(event)

      expect(run.reload).to be_failed
      expect(run.last_error).to eq('Asynchronous delivery failure')
    end

    it 'marks a completed run as failed by the run id stored on its outgoing message' do
      run.update!(status: :completed, current_node_id: nil)
      message.update!(content_attributes: message.content_attributes.merge('whatsapp_automation_run_id' => run.id))
      message.update!(status: :failed, external_error: 'Late delivery failure')

      listener.message_updated(event)

      expect(run.reload).to be_failed
      expect(run.last_error).to eq('Late delivery failure')
    end
  end
end
