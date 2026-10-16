require 'rails_helper'

RSpec.describe MarcosxAi::ReplyBatchRunner do
  include ActiveJob::TestHelper
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:assistant) { account.marcosx_ai_assistants.create!(name: 'Support', config: { response_delay_seconds: 0 }) }
  let(:inbox) { create(:channel_whatsmeow, account: account).inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let!(:message) { create(:message, account: account, inbox: inbox, conversation: conversation, content: 'Please help') }
  let(:batch) { assistant.reply_batches.create!(account: account, user: user, mode: 'review', request_id: SecureRandom.uuid) }
  let(:item) { batch.items.create!(conversation: conversation, trigger_message_id: message.id, assistant_version: assistant.updated_at.iso8601(6)) }
  let(:plan) {
    { 'messages' => ['A helpful answer'], 'voice_text' => nil, 'resource_ids' => [], 'pix_key_id' => nil, 'reaction' => nil,
      'reaction_message_id' => nil, 'handoff' => false, 'handoff_reason' => nil, 'alert_rule_ids' => [], 'recall_context' => false }
  }

  before do
    assistant.marcosx_ai_inboxes.create!(account: account, inbox: inbox)
    account.marcosx_ai_credentials.create!(provider: 'openai', api_key: 'test', enabled: true)
    allow(MarcosxAi::BatchReplyPlanner).to receive(:perform).and_return(plan)
  end

  it 'prepares reviews without enabling support or sending messages' do
    item
    expect { described_class.new(batch).perform }.not_to change(Message.outgoing, :count)
    expect(item.reload.status).to eq('ready')
    described_class.new(batch).perform
    expect(batch.reload.status).to eq('ready')
    expect(assistant.reload.auto_response_enabled?).to be(false)
  end

  it 'sends directly while general support is off and preserves an individual pause' do
    state = MarcosxAi::ConversationState.for_conversation!(conversation, assistant: assistant)
    state.pause_by_agent!
    batch.update!(mode: 'direct')
    item
    described_class.new(batch).perform
    expect(item.reload.status).to eq('sending')
    MarcosxAi::DeliveryJob.perform_now(conversation.id, item.run_token, 0)
    expect(conversation.messages.outgoing.where(private: false).pluck(:content)).to eq(['A helpful answer'])
    expect(item.reload.status).to eq('sent')
    expect(state.reload.status).to eq('paused_by_agent')
    expect(state.metadata['manual_activation']).not_to be(true)
    described_class.new(batch).perform
    expect(batch.reload.status).to eq('completed')
    MarcosxAi::DeliveryJob.perform_now(conversation.id, item.run_token, 0)
    expect(conversation.messages.outgoing.where(private: false).count).to eq(1)
  end

  it 'skips a review if a human answered before sending' do
    item.update!(status: 'queued', plan: plan)
    batch.update!(status: 'running')
    create(:message, :outgoing, account: account, inbox: inbox, conversation: conversation, sender: user)
    described_class.new(batch).perform
    expect(item.reload.status).to eq('skipped')
    expect(MarcosxAi::BatchReplyPlanner).not_to have_received(:perform)
  end

  it 'skips a review when a new incoming message or agent configuration changes' do
    item
    create(:message, account: account, inbox: inbox, conversation: conversation)
    described_class.new(batch).perform
    expect(item.reload.status).to eq('skipped')
    expect(conversation.messages.outgoing.where(private: false)).to be_empty
  end

  it 'removes only the selected review and preserves conversation activation' do
    state = MarcosxAi::ConversationState.for_conversation!(conversation, assistant: assistant)
    state.resume!(manual: true)
    item.update!(status: 'ready', plan: plan)
    item.discard!
    expect(item.reload.status).to eq('discarded')
    expect(state.reload.metadata['manual_activation']).to be(true)
    expect(state.status).to eq('active')
  end

  it 'cancels delivery already queued without sending or erasing manual membership' do
    batch.update!(mode: 'direct')
    item
    described_class.new(batch).perform
    token = item.reload.run_token
    expect(item.status).to eq('sending')
    batch.cancel!
    MarcosxAi::DeliveryJob.perform_now(conversation.id, token, 0)
    expect(conversation.messages.outgoing.where(private: false)).to be_empty
    expect(conversation.reload.marcosx_ai_conversation_state.metadata['processing']).to be(false)
  end

  it 'shows a failure and advances instead of silently dropping the remaining queue' do
    item
    allow(MarcosxAi::BatchReplyPlanner).to receive(:perform).and_raise(StandardError, 'provider failed')
    expect { described_class.new(batch).perform }.to have_enqueued_job(MarcosxAi::ReplyBatchJob)
    expect(item.reload.status).to eq('failed')
  end

  it 'does not cancel the new automatic reply when an incoming message supersedes a batch' do
    assistant.update!(config: assistant.resolved_config.merge(auto_response_enabled: true))
    batch.update!(mode: 'direct')
    item
    described_class.new(batch).perform
    incoming = create(:message, account: account, inbox: inbox, conversation: conversation.reload, content: 'A newer question')
    MarcosxAi::ResponseScheduler.perform(message: incoming)
    state = MarcosxAi::ConversationState.find_by!(conversation: conversation)
    new_token = state.metadata['run_token']
    expect(state.metadata['reply_batch_item_id']).to be_nil
    described_class.new(batch).perform
    expect(item.reload.status).to eq('skipped')
    expect(state.reload.current_run?(new_token)).to be(true)
  end

  it 'continues preparing other items if the operator discards one during generation' do
    item
    allow(MarcosxAi::BatchReplyPlanner).to receive(:perform) { item.discard!; plan }
    expect { described_class.new(batch).perform }.to have_enqueued_job(MarcosxAi::ReplyBatchJob)
    expect(item.reload.status).to eq('discarded')
  end

  it 'delivers the reviewed audio bytes without synthesizing the voice again' do
    assistant.update!(config: assistant.resolved_config.deep_merge(voice: { enabled: true, minimax: { voice_id: 'test_voice' } }))
    assistant.voice_credentials.create!(account: account, provider: 'minimax', api_key: 'voice-test')
    voice = instance_double(MarcosxAi::VoiceClient)
    allow(MarcosxAi::VoiceClient).to receive(:new).and_return(voice)
    expect(voice).to receive(:synthesize).with('The reviewed answer').once.and_return('ID3-reviewed-bytes')
    allow(MarcosxAi::BatchReplyPlanner).to receive(:perform).and_return(plan.merge('voice_text' => 'The reviewed answer'))
    item
    described_class.new(batch).perform
    expect(item.reload.audio.download).to eq('ID3-reviewed-bytes')
    item.update!(status: 'queued')
    batch.update!(status: 'running')
    described_class.new(batch).perform
    MarcosxAi::DeliveryJob.perform_now(conversation.id, item.reload.run_token, 0)
    audio = conversation.messages.outgoing.where(private: false).last.attachments.first
    expect(audio.file.download).to eq('ID3-reviewed-bytes')
    expect(item.reload.status).to eq('sent')
  end

  it 'prevents two batches from reserving the same unanswered turn' do
    item
    other = assistant.reply_batches.create!(account: account, user: user, mode: 'direct', request_id: SecureRandom.uuid)
    expect {
      MarcosxAi::ReplyBatchItem.transaction(requires_new: true) do
        other.items.create!(conversation: conversation, trigger_message_id: message.id, assistant_version: assistant.updated_at.iso8601(6))
      end
    }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'excludes historical imports, groups, resolved conversations and answered turns from candidates' do
    pending = MarcosxAi::PendingConversations.new(assistant: assistant, user: user)
    expect(pending.eligible?(conversation)).to be(true)
    conversation.update!(additional_attributes: { whatsmeow_group: true })
    expect(pending.scope).not_to include(conversation)
    conversation.update!(additional_attributes: {}, status: :resolved)
    expect(pending.scope).not_to include(conversation)
    conversation.update!(status: :open)
    message.update!(content_attributes: { historical: true })
    expect(pending.scope).not_to include(conversation)
  end

  it 'suspends and restores manually enabled sessions without changing the selected people or their pauses' do
    state = MarcosxAi::ConversationState.for_conversation!(conversation, assistant: assistant)
    state.resume!(manual: true)
    assistant.update!(config: assistant.resolved_config.merge(manual_sessions_enabled: false, auto_response_enabled: true))
    expect(state.reload.enabled_for_ai?).to be(false)
    expect(state.metadata['manual_activation']).to be(true)
    state.pause_by_agent!
    assistant.update!(config: assistant.resolved_config.merge(manual_sessions_enabled: true))
    expect(state.reload.enabled_for_ai?).to be(true)
    expect(state.active_for_ai?).to be(false)
  end
end
