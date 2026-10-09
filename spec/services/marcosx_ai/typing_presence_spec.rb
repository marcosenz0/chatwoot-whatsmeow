require 'rails_helper'

RSpec.describe MarcosxAi::TypingPresenceJob do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let!(:credential) { account.marcosx_ai_credentials.create!(provider: 'openai', api_key: 'test', enabled: true) }
  let(:assistant) { account.marcosx_ai_assistants.create!(name: 'Support', config: { auto_response_enabled: false }) }
  let(:channel) { create(:channel_whatsmeow, account: account, typing_enabled: true) }
  let(:conversation) { create(:conversation, account: account, inbox: channel.inbox) }
  let(:message) { create(:message, account: account, inbox: channel.inbox, conversation: conversation) }
  let(:state) { MarcosxAi::ConversationState.for_conversation!(conversation, assistant: assistant) }
  let(:client) { instance_double(Whatsmeow::SessionClient, typing: {}) }
  let(:token) { state.reload.metadata.fetch('run_token') }

  before do
    assistant.marcosx_ai_inboxes.create!(account: account, inbox: channel.inbox)
    allow(Whatsmeow::SessionClient).to receive(:new).and_return(client)
    conversation.contact_inbox.update!(source_id: '556399999999@s.whatsapp.net')
    state.resume!(manual: true)
    MarcosxAi::ResponseScheduler.perform(message: message)
    clear_enqueued_jobs
  end

  it 'renews text presence during an individual reply with general support off' do
    expect { described_class.perform_now(conversation.id, token) }.to have_enqueued_job(described_class).with(conversation.id, token)
    expect(client).to have_received(:typing).with(to: anything, state: 'composing', media: 'text')
  end

  it 'clears presence immediately when the operator pauses and ignores the old renewal' do
    old_token = token
    described_class.perform_now(conversation.id, old_token)
    state.pause_by_agent!
    expect(client).to have_received(:typing).with(to: anything, state: 'paused', media: 'text')
    clear_enqueued_jobs
    expect { described_class.perform_now(conversation.id, old_token) }.not_to have_enqueued_job(described_class)
    expect(client).to have_received(:typing).with(to: anything, state: 'composing', media: 'text').once
  end

  it 'does not renew when the agent typing option is off' do
    assistant.update!(config: assistant.resolved_config.merge(show_typing: false))
    MarcosxAi::ResponseScheduler.perform(message: message)
    clear_enqueued_jobs
    expect { described_class.perform_now(conversation.id, token) }.not_to have_enqueued_job(described_class)
    expect(client).not_to have_received(:typing).with(to: anything, state: 'composing', media: 'text')
  end

  it 'clears presence on completion even when the inbox typing setting was switched off' do
    described_class.perform_now(conversation.id, token)
    channel.update!(typing_enabled: false)
    state.update!(metadata: state.metadata.merge('processing' => false))
    expect(client).to have_received(:typing).with(to: anything, state: 'paused', media: 'text')
  end

  it 'uses audio presence only when the recording option allows it' do
    assistant.update!(config: assistant.resolved_config.merge(show_recording: false))
    Whatsmeow::TypingStatusService.new(conversation: conversation.reload, status: 'on', media: 'audio').perform
    expect(client).not_to have_received(:typing).with(to: anything, state: 'composing', media: 'audio')
    assistant.update!(config: assistant.resolved_config.merge(show_recording: true))
    Whatsmeow::TypingStatusService.new(conversation: conversation.reload, status: 'on', media: 'audio').perform
    expect(client).to have_received(:typing).with(to: anything, state: 'composing', media: 'audio')
  end
end
