require 'rails_helper'

RSpec.describe Whatsmeow::OpenConversationMergeService do
  subject(:service) { described_class.new(inbox: inbox, contact: contact, contact_inbox: canonical_inbox, source_ids: source_ids) }

  let(:account) { create(:account) }
  let(:inbox) { create(:channel_whatsmeow, account: account).inbox }
  let(:contact) { create(:contact, account: account) }
  let(:source_ids) { ['15551234567@s.whatsapp.net', '123456789@lid'] }
  let(:canonical_inbox) { create(:contact_inbox, inbox: inbox, contact: contact, source_id: source_ids.first) }
  let(:alias_inbox) { create(:contact_inbox, inbox: inbox, contact: contact, source_id: source_ids.last) }
  let!(:target) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: canonical_inbox) }
  let!(:source) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: alias_inbox) }
  let(:assistant) { account.marcosx_ai_assistants.create!(name: 'Support') }
  let!(:source_state) { MarcosxAi::ConversationState.for_conversation!(source, assistant: assistant) }
  let(:target_state) { MarcosxAi::ConversationState.for_conversation!(target, assistant: assistant) }

  it 'preserves AI activity and state when the alias conversation is merged' do
    message = create(:message, account: account, inbox: inbox, conversation: source, sender: contact, source_id: 'real-message-id')
    log = MarcosxAi::Log.create!(account: account, assistant: assistant, conversation: source, event: 'response_sent')
    source_state.update!(metadata: { 'run_token' => 'obsolete', 'processing' => true, 'pending_response' => { 'messages' => ['Old reply'] },
                                    'conversation_summary' => 'Old summary', 'summary_cursor' => { 'id' => message.id } })

    expect { service.perform }.not_to raise_error

    expect(Conversation.exists?(source.id)).to be(false)
    expect(message.reload.conversation_id).to eq(target.id)
    expect(message.source_id).to eq('real-message-id')
    expect(log.reload.conversation_id).to eq(target.id)
    expect(source_state.reload.conversation_id).to eq(target.id)
    expect(source_state.status).to eq('active')
    expect(source_state.metadata['processing']).to be(false)
    expect(source_state.metadata['run_token']).not_to eq('obsolete')
    expect(source_state.metadata).not_to include('pending_response', 'conversation_summary', 'summary_cursor')
  end

  it 'keeps a permanent human takeover when the canonical conversation was active' do
    target_state
    human_message = create(:message, :outgoing, account: account, inbox: inbox, conversation: source)
    source_state.pause_by_human!(message: human_message, minutes: 0)

    service.perform

    expect(target_state.reload.status).to eq('paused_by_human')
    expect(target_state.paused_until).to be_nil
    expect(target_state.last_human_message_id).to eq(human_message.id)
    expect(target_state.metadata['paused_reason']).to eq('human_response')
    expect(MarcosxAi::ConversationState.exists?(source_state.id)).to be(false)
    expect(MarcosxAi::ConversationState.where(conversation: target).count).to eq(1)
  end

  it 'keeps a manual pause on the canonical conversation' do
    target_state.pause_by_agent!(reason: 'operator_paused')

    service.perform

    expect(target_state.reload.status).to eq('paused_by_agent')
    expect(target_state.metadata['paused_reason']).to eq('operator_paused')
    expect(target_state.metadata['processing']).to be(false)
  end

  it 'keeps the longer of two temporary human pauses' do
    human_message = create(:message, :outgoing, account: account, inbox: inbox, conversation: source)
    target_state.pause_by_human!(message: human_message, minutes: 5)
    source_state.pause_by_human!(message: human_message, minutes: 30)
    paused_until = source_state.paused_until

    service.perform

    expect(target_state.reload.status).to eq('paused_by_human')
    expect(target_state.paused_until).to eq(paused_until)
  end

  it 'removes AI activity when its conversation is explicitly deleted' do
    log = MarcosxAi::Log.create!(account: account, assistant: assistant, conversation: source, event: 'response_sent')

    expect { source.destroy! }.not_to raise_error

    expect(MarcosxAi::Log.exists?(log.id)).to be(false)
    expect(MarcosxAi::ConversationState.exists?(source_state.id)).to be(false)
  end
end
