require 'rails_helper'

RSpec.describe 'MarcoXIA memory and human assistance' do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: user) }
  let(:assistant) { account.marcosx_ai_assistants.create!(name: 'Support', config: { memory_mode: 'summary_recent' }) }
  let(:state) { MarcosxAi::ConversationState.for_conversation!(conversation, assistant: assistant) }
  let(:client) { instance_double(MarcosxAi::ProviderClient) }
  let(:rule) { { id: 'help', name: 'Help', description: 'Needs a person', action: 'pause', message: '{reason}', user_ids: [user.id] } }

  it 'summarizes 480 messages, retains 20 recent and incrementally processes messages leaving the window' do
    now = Time.current
    rows = 500.times.map do |index|
      { account_id: account.id, inbox_id: inbox.id, conversation_id: conversation.id, content: "Decision #{index}",
        message_type: 0, content_type: 0, status: 0, private: false, created_at: now + index.seconds, updated_at: now }
    end
    Message.insert_all!(rows)
    latest = conversation.messages.order(:id).last
    state.update!(metadata: { context_messages_limit: 20 })
    allow(client).to receive(:chat).and_return('Decision 0 remains pending')
    context = MarcosxAi::ConversationContext.new(conversation: conversation, assistant: assistant, state: state, client: client,
                                                 trigger_message: latest, token: 'memory', valid_run: -> { true })
    messages = context.messages
    expect(messages.size).to eq(21)
    expect(messages.first[:content]).to include('Decision 0')
    expect(state.reload.metadata['summary_messages_count']).to eq(480)
    expect(client).to have_received(:chat).exactly(4).times
    context.messages
    expect(client).to have_received(:chat).exactly(4).times
    Message.insert_all!([rows.last.merge(content: 'New question', created_at: now + 501.seconds)])
    context = MarcosxAi::ConversationContext.new(conversation: conversation, assistant: assistant, state: state, client: client,
                                                 trigger_message: conversation.messages.order(:id).last, token: 'memory', valid_run: -> { true })
    context.messages
    expect(client).to have_received(:chat).exactly(5).times
    expect(state.reload.metadata['summary_messages_count']).to eq(481)
    conversation.messages.order(:id).first.update_columns(content: 'Corrected decision', updated_at: now + 600.seconds)
    context.messages
    expect(client).to have_received(:chat).exactly(9).times
    state.update!(metadata: state.metadata.merge('context_messages_limit' => 40))
    context = MarcosxAi::ConversationContext.new(conversation: conversation, assistant: assistant, state: state, client: client,
                                                 trigger_message: conversation.messages.order(:id).last, token: 'memory', valid_run: -> { true })
    expect(context.messages.size).to eq(41)
    expect(state.reload.metadata['summary_messages_count']).to eq(461)
  end

  it 'keeps selected-only context free of notes, old memory and operational notifications' do
    create(:message, account: account, inbox: inbox, conversation: conversation, private: true, content: 'Secret note')
    create(:message, account: account, inbox: inbox, conversation: conversation, additional_attributes: { marcosx_ai_operational: true },
                     content: 'Operational notice')
    latest = create(:message, account: account, inbox: inbox, conversation: conversation, content: 'Actual question')
    state.update!(metadata: { memory_mode: 'selected_only', context_messages_limit: 20, conversation_summary: 'Old secret' })
    messages = MarcosxAi::ConversationContext.new(conversation: conversation, assistant: assistant, state: state, client: client,
                                                  trigger_message: latest, token: 'memory', valid_run: -> { true }).messages
    expect(messages.size).to eq(1)
    expect(messages.to_json).not_to include('Secret', 'Operational', 'Old secret')
  end

  it 'invalidates deleted history and imported older messages while preserving the recent window' do
    rows = 5.times.map do |index|
      create(:message, account: account, inbox: inbox, conversation: conversation, content: "Fact #{index}",
                       created_at: 10.minutes.ago + index.seconds)
    end
    state.update!(metadata: { memory_mode: 'summary_recent', context_messages_limit: 2 })
    allow(client).to receive(:chat).and_return('Previous facts')
    build_context = -> {
      MarcosxAi::ConversationContext.new(conversation: conversation, assistant: assistant, state: state, client: client,
                                         trigger_message: conversation.messages.order(:id).last, token: 'test', valid_run: -> { true })
    }
    build_context.call.messages
    expect(state.reload.metadata['summary_messages_count']).to eq(3)
    rows.first.update!(content_attributes: { deleted: true })
    expect(MarcosxAi::ConversationContext.stale?(state)).to be(true)
    build_context.call.messages
    expect(state.reload.metadata['summary_messages_count']).to eq(2)
    create(:message, account: account, inbox: inbox, conversation: conversation, content: 'Imported old decision',
                     created_at: 1.day.ago, content_attributes: { historical: true })
    messages = build_context.call.messages
    expect(messages.size).to eq(3)
    expect(state.reload.metadata['summary_messages_count']).to eq(3)
    expect(client).to have_received(:chat).exactly(3).times
    expect(messages.to_json).not_to include('Fact 0')
  end

  it 'opens one alert per pending rule, pauses before delivery and keeps the assignee' do
    assistant.update!(config: assistant.config.merge(alert_rules: [rule]))
    plan = { 'alert_rule_ids' => ['help'], 'handoff' => false }
    state.with_lock { MarcosxAi::AlertService.perform(state: state, plan: plan) }
    state.with_lock { MarcosxAi::AlertService.perform(state: state, plan: plan) }
    expect(MarcosxAi::Alert.where(conversation: conversation).count).to eq(1)
    expect(state.reload.status).to eq('awaiting_human')
    expect(conversation.reload.assignee_id).to eq(user.id)
    delivery = MarcosxAi::AlertDelivery.last
    MarcosxAi::AlertDeliveryJob.perform_now(delivery.id)
    MarcosxAi::AlertDeliveryJob.perform_now(delivery.id)
    expect(Notification.where(user: user, notification_type: :marcosx_ai_attention).count).to eq(1)
    alert = delivery.alert
    alert.update!(status: 'resolved', resolved_by: user, resolved_at: Time.current)
    expect(state.reload.status).to eq('awaiting_human')
    state.with_lock { MarcosxAi::AlertService.perform(state: state, plan: plan) }
    expect(MarcosxAi::Alert.where(conversation: conversation).count).to eq(2)
  end

  it 'notifies without pausing, ignores unconfigured rule IDs and shows delivery failure' do
    assistant.update!(config: assistant.config.merge(alert_rules: [rule.merge(action: 'notify', user_ids: [123_456_789])]))
    state.with_lock { MarcosxAi::AlertService.perform(state: state, plan: { 'alert_rule_ids' => ['unknown'], 'handoff' => false }) }
    expect(MarcosxAi::Alert.count).to eq(0)
    state.with_lock { MarcosxAi::AlertService.perform(state: state, plan: { 'alert_rule_ids' => ['help'], 'handoff' => false }) }
    expect(state.reload.status).to eq('active')
    delivery = MarcosxAi::AlertDelivery.last
    MarcosxAi::AlertDeliveryJob.perform_now(delivery.id)
    expect(delivery.reload.status).to eq('failed')
    expect(delivery.public_data[:error]).to be_present
  end

  it 'does not resume before a human reply, and manual pause defeats a scheduled return' do
    assistant.update!(config: assistant.config.merge(resume_mode: 'after_human', resume_after_minutes: 15))
    state.wait_for_human!(reason: 'Help')
    expect(state.reload.paused_until).to be_nil
    human = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, sender: user)
    state.pause_by_human!(message: human, minutes: 0)
    due = state.paused_until.iso8601(6)
    travel 16.minutes do
      state.pause_by_agent!(reason: 'manual_pause')
      MarcosxAi::ResumeJob.perform_now(state.id, human.id, due)
      expect(state.reload.status).to eq('paused_by_agent')
    end
  end

  it 'keeps native alerts when generic notification cleanup runs' do
    alert = Notification.create!(account: account, user: user, primary_actor: conversation, notification_type: :marcosx_ai_attention)
    normal = Notification.create!(account: account, user: user, primary_actor: conversation, notification_type: :conversation_assignment)
    Notification::RemoveDuplicateNotificationJob.perform_now(normal)
    expect(Notification.exists?(alert.id)).to be true
  end

  it 'restarts the timer after the latest human reply and resumes only when that interval expires' do
    assistant.update!(config: assistant.config.merge(resume_mode: 'after_human', resume_after_minutes: 15))
    state.wait_for_human!(reason: 'Help')
    human = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, sender: user)
    state.pause_by_human!(message: human, minutes: 0)
    old_due = state.paused_until.iso8601(6)
    travel 10.minutes do
      latest = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, sender: user)
      state.pause_by_human!(message: latest, minutes: 0)
      new_due = state.paused_until.iso8601(6)
      travel 6.minutes do
        MarcosxAi::ResumeJob.perform_now(state.id, human.id, old_due)
        expect(state.reload.status).to eq('paused_by_human')
        MarcosxAi::ResumeJob.perform_now(state.id, latest.id, new_due)
        expect(state.reload.status).to eq('paused_by_human')
        travel 10.minutes do
          MarcosxAi::ResumeJob.perform_now(state.id, latest.id, new_due)
          expect(state.reload.status).to eq('active')
          expect(state.metadata).not_to have_key('human_wait')
        end
      end
    end
  end

  it 'creates separate operational deliveries for multiple WhatsApp recipients without AI loops' do
    direct_inbox = create(:channel_whatsmeow, account: account).inbox
    target = create(:conversation, account: account, inbox: direct_inbox)
    assistant.update!(config: assistant.config.merge(notifications: {
      user_ids: [user.id], whatsapp_numbers: ['+15555550101', '+15555550102'], inbox_id: direct_inbox.id
    }, alert_rules: [rule.merge(action: 'notify')]))
    state.with_lock { MarcosxAi::AlertService.perform(state: state, plan: { 'alert_rule_ids' => ['help'] }) }
    deliveries = MarcosxAi::AlertDelivery.where(kind: 'whatsapp')
    expect(deliveries.count).to eq(2)
    allow(Whatsmeow::DirectConversationBuilder).to receive(:new).and_return(instance_double(Whatsmeow::DirectConversationBuilder, perform: target))
    deliveries.each do |delivery|
      2.times { MarcosxAi::AlertDeliveryJob.perform_now(delivery.id) }
      expect(delivery.reload.status).to eq('queued')
      expect(delivery.message.additional_attributes['marcosx_ai_operational']).to be(true)
    end
    expect(target.messages.count).to eq(2)
    expect(MarcosxAi::ConversationContext.public_history(target)).to be_empty
    expect(target.reload.marcosx_ai_conversation_state).to be_nil
  end

  it 'does not disclose another account through approved context metadata' do
    other = create(:conversation)
    state.update!(metadata: { approved_context_links: [{ conversation_id: other.id, approved_by: user.id }] })
    expect(MarcosxAi::LinkedContext.new(state: state).messages).to be_empty
  end
end
