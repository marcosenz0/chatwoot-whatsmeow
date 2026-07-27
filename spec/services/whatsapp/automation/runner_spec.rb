require 'rails_helper'

describe Whatsapp::Automation::Runner do
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
  let(:definition) do
    {
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
  end
  let(:automation) do
    WhatsappAutomation.create!(
      account: account,
      inbox: inbox,
      name: 'Order updates',
      trigger_type: 'any_message',
      definition: definition,
      status: :active,
      published_at: Time.current
    )
  end
  let(:run) do
    WhatsappAutomationRun.create!(
      account: account,
      whatsapp_automation: automation,
      contact: contact,
      conversation: conversation,
      status: :queued,
      current_node_id: 'message'
    )
  end

  describe '#perform' do
    it 'serializes concurrent runners and sends the current message node once' do
      runners = Array.new(2) { described_class.new(run: WhatsappAutomationRun.find(run.id)) }
      barrier = Concurrent::CyclicBarrier.new(runners.length)
      errors = Concurrent::Array.new

      threads = runners.map do |runner|
        Thread.new do
          barrier.wait
          runner.perform
        rescue StandardError => e
          errors << e
        end
      end

      threads.each(&:join)

      expect(errors).to be_empty
      expect(run.reload).to be_running

      messages = conversation.messages.outgoing.where("content_attributes ->> 'whatsapp_automation_id' = ?", automation.id.to_s)
      expect(messages.count).to eq(1)
      expect(run.current_node_id).to eq('message')
      expect(run.context).to include(
        'awaiting_message_id' => messages.first.id,
        'awaiting_node_id' => 'message'
      )

      messages.first.update!(source_id: 'wamid.accepted')
      described_class.new(run: run).perform

      expect(run.reload).to be_completed
      expect(messages.reload.count).to eq(1)
    end

    it 'keeps a pending message paused without sending it again' do
      described_class.new(run: run).perform
      pending_message_id = run.reload.context['awaiting_message_id']

      expect do
        described_class.new(run: run).perform
      end.not_to(change do
        conversation.messages.outgoing.where("content_attributes ->> 'whatsapp_automation_id' = ?", automation.id.to_s).count
      end)

      expect(run.reload).to be_running
      expect(run.current_node_id).to eq('message')
      expect(run.context['awaiting_message_id']).to eq(pending_message_id)
    end

    it 'advances an accepted message without sending it again' do
      described_class.new(run: run).perform
      message = Message.find(run.reload.context['awaiting_message_id'])
      message.update!(source_id: 'wamid.accepted')

      expect do
        described_class.new(run: run).perform
      end.not_to(change do
        conversation.messages.outgoing.where("content_attributes ->> 'whatsapp_automation_id' = ?", automation.id.to_s).count
      end)

      expect(run.reload).to be_completed
      expect(run.current_node_id).to be_nil
      expect(run.context).not_to include('awaiting_message_id', 'awaiting_node_id')
    end

    it 'fails the run when WhatsApp rejects the pending message' do
      described_class.new(run: run).perform
      message = Message.find(run.reload.context['awaiting_message_id'])
      message.update!(status: :failed, external_error: 'Meta rejected the message')

      expect do
        described_class.new(run: run).perform
      end.not_to(change do
        conversation.messages.outgoing.where("content_attributes ->> 'whatsapp_automation_id' = ?", automation.id.to_s).count
      end)

      expect(run.reload).to be_failed
      expect(run.last_error).to eq('Meta rejected the message')
    end

    it 'reloads and rechecks the run state after acquiring the lock' do
      stale_run = WhatsappAutomationRun.find(run.id)
      run.update!(status: :completed, current_node_id: nil)

      expect(Messages::MessageBuilder).not_to receive(:new)

      described_class.new(run: stale_run).perform

      expect(stale_run).to be_completed
    end

    it 'keeps reply-waiting runs paused' do
      run.update!(status: :waiting_reply)

      expect(Messages::MessageBuilder).not_to receive(:new)

      described_class.new(run: run).perform

      expect(run.reload).to be_waiting_reply
      expect(run.current_node_id).to eq('message')
    end

    it 'cancels a queued run when its automation is no longer enabled' do
      automation.update!(status: :paused, published_at: nil)

      expect(Messages::MessageBuilder).not_to receive(:new)

      described_class.new(run: run).perform

      expect(run.reload).to be_cancelled
      expect(run.next_run_at).to be_nil
    end

    it 'reschedules a wait that is not due without executing its next node' do
      next_run_at = 1.hour.from_now
      run.update!(status: :waiting, next_run_at: next_run_at)

      expect(Messages::MessageBuilder).not_to receive(:new)

      expect { described_class.new(run: run).perform }
        .to have_enqueued_job(Whatsapp::Automation::RunJob).with(run.id).at(next_run_at)

      expect(run.reload).to be_waiting
      expect(run.next_run_at).to be_within(1.second).of(next_run_at)
    end

    context 'when the message has reply buttons' do
      let(:definition) do
        super().deep_dup.tap do |value|
          value['nodes'].first['config']['buttons'] = [
            { 'id' => 'yes', 'title' => 'Yes' },
            { 'id' => 'no', 'title' => 'No' }
          ]
        end
      end

      it 'waits for the reply only after WhatsApp accepts the message' do
        described_class.new(run: run).perform

        expect(run.reload).to be_running
        message = Message.find(run.context['awaiting_message_id'])
        message.update!(source_id: 'wamid.accepted')

        expect do
          described_class.new(run: run).perform
        end.not_to(change do
          conversation.messages.outgoing.where("content_attributes ->> 'whatsapp_automation_id' = ?", automation.id.to_s).count
        end)

        expect(run.reload).to be_waiting_reply
        expect(run.current_node_id).to eq('message')
        expect(run.context['expected_buttons']).to eq(definition['nodes'].first['config']['buttons'])
        expect(run.context).not_to include('awaiting_message_id', 'awaiting_node_id')
      end
    end
  end
end
