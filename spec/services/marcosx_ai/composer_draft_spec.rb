require 'rails_helper'

RSpec.describe MarcosxAi::ComposerDraftService do
  let(:account) { create(:account) }
  let!(:credential) { account.marcosx_ai_credentials.create!(provider: 'openai', api_key: 'test', enabled: true) }
  let(:assistant) { account.marcosx_ai_assistants.create!(name: 'Support', instructions: 'Never invent prices', config: { timezone: 'America/Araguaina' }) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:client) { instance_double(MarcosxAi::ProviderClient) }
  let(:plan) { { messages: ['Draft for review'], reaction: nil, reaction_message_id: nil, handoff: false, handoff_reason: nil }.to_json }

  before do
    assistant.marcosx_ai_inboxes.create!(account: account, inbox: inbox)
    allow(MarcosxAi::ProviderClient).to receive(:new).and_return(client)
    allow(client).to receive(:chat).and_return(plan)
  end

  it 'uses the configured instructions and temporal public context without creating AI state or sending' do
    create(:message, conversation: conversation, account: account, inbox: inbox, content: 'Question yesterday', created_at: 1.day.ago)
    create(:message, conversation: conversation, account: account, inbox: inbox, private: true, content: 'Private secret')
    expect {
      result = described_class.new(conversation: conversation, action: 'reply_suggestion').perform
      expect(result).to include(content: 'Draft for review', assistant_name: 'Support')
    }.not_to change(MarcosxAi::ConversationState, :count)
    expect(conversation.messages.outgoing.where(private: false)).to be_empty
    expect(client).to have_received(:chat) do |messages:, schema:|
      expect(messages.to_json).to include('Never invent prices', 'Question yesterday', 'sent_at', '-03:00')
      expect(messages.to_json).not_to include('Private secret')
      expect(schema).to eq(MarcosxAi::ReplyPlan::SCHEMA)
    end
  end

  it 'honors the chosen history limit and preserves an active state and its pending run' do
    create(:message, conversation: conversation, account: account, inbox: inbox, content: 'Outside context')
    create(:message, conversation: conversation, account: account, inbox: inbox, content: 'Latest question')
    state = MarcosxAi::ConversationState.for_conversation!(conversation, assistant: assistant)
    state.resume!(manual: true)
    state.update!(metadata: state.metadata.merge('context_messages_limit' => 1, 'run_token' => 'keep-this-run'))
    original = state.attributes
    described_class.new(conversation: conversation.reload, action: 'reply_suggestion').perform
    expect(state.reload.attributes).to eq(original)
    expect(client).to have_received(:chat) do |messages:, **|
      expect(messages.to_json).to include('Latest question')
      expect(messages.to_json).not_to include('Outside context')
    end
  end

  it 'rejects a result if a new public message arrives during generation' do
    create(:message, conversation: conversation, account: account, inbox: inbox)
    allow(client).to receive(:chat) do
      create(:message, conversation: conversation, account: account, inbox: inbox, content: 'New question')
      plan
    end
    expect {
      described_class.new(conversation: conversation, action: 'reply_suggestion').perform
    }.to raise_error(CustomExceptions::MarcosxAi, I18n.t('marcosx_ai.errors.analysis_outdated'))
  end

  it 'supports summary and refinement through the same agent without executing a handoff' do
    create(:message, conversation: conversation, account: account, inbox: inbox)
    described_class.new(conversation: conversation, action: 'summarize').perform
    described_class.new(conversation: conversation, action: 'refine', content: 'Previous draft', instruction: 'Make it shorter').perform
    expect(client).to have_received(:chat).with(messages: array_including(hash_including(content: /Make it shorter/)), schema: anything)
    expect(conversation.reload.status).to eq('open')
    expect(conversation.messages.outgoing.where(private: false)).to be_empty
  end

  it 'rejects unknown actions and an empty rewrite' do
    expect { described_class.new(conversation: conversation, action: 'ask_copilot').perform }.to raise_error(CustomExceptions::MarcosxAi)
    expect { described_class.new(conversation: conversation, action: 'improve', content: '').perform }.to raise_error(CustomExceptions::MarcosxAi)
    expect(client).not_to have_received(:chat)
  end
end
