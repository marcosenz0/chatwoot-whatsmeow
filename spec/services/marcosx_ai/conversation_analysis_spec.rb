require 'rails_helper'

RSpec.describe MarcosxAi::ConversationAnalysisService do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let!(:credential) { account.marcosx_ai_credentials.create!(provider: 'openai', api_key: 'test', enabled: true) }
  let(:assistant) { account.marcosx_ai_assistants.create!(name: 'Felipe', config: { auto_response_enabled: true, auto_start: false }) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:state) { MarcosxAi::ConversationState.choose_for_conversation!(conversation, assistant: assistant) }
  let(:service) { described_class.new(state: state) }
  let(:client) { instance_double(MarcosxAi::ProviderClient) }
  let(:plan) do
    { messages: ['Thanks, I understand.'], reaction: nil, reaction_message_id: nil, handoff: false, handoff_reason: nil,
      summary: 'The customer prefers concise replies.', next_step: 'Acknowledge their preference.' }
  end
  let!(:incoming) { create(:message, account: account, inbox: inbox, conversation: conversation, content: 'Keep it short, please') }

  before do
    allow(MarcosxAi::ProviderClient).to receive(:new).and_return(client)
    allow(client).to receive(:chat).and_return(plan.to_json)
    clear_enqueued_jobs
  end

  it 'starts a review with AI paused and schedules analysis without sending a message' do
    expect { service.start! }.to have_enqueued_job(MarcosxAi::ConversationAnalysisJob)
    expect(state.reload.status).to eq('paused_by_agent')
    expect(service.report['status']).to eq('processing')
    expect(conversation.messages.outgoing).to be_empty
    expect(client).not_to have_received(:chat)
  end

  it 'analyzes the public history but excludes private notes and call events' do
    create(:message, account: account, inbox: inbox, conversation: conversation, private: true, content: 'Private instructions')
    create(:message, account: account, inbox: inbox, conversation: conversation, content_type: :voice_call)
    service.start!
    service.perform(service.report['id'])
    expect(service.report).to include('status' => 'ready', 'messages_count' => 1, 'summary' => plan[:summary], 'next_step' => plan[:next_step])
    expect(client).to have_received(:chat) do |messages:, schema:|
      expect(messages.last[:content]).to include('Keep it short')
      expect(messages.to_json).not_to include('Private instructions')
      expect(schema[:required]).to include('summary', 'next_step')
    end
    expect(conversation.messages.outgoing).to be_empty
  end

  it 'sends the reviewed reply once and keeps individual support active' do
    service.start!
    token = service.report['id']
    service.perform(token)
    expect { service.send!(token: token, messages: ['Edited reply']) }.to have_enqueued_job(MarcosxAi::DeliveryJob)
    run = state.reload.metadata['run_token']
    MarcosxAi::DeliveryJob.perform_now(conversation.id, run, 0)
    expect(conversation.messages.outgoing.where(private: false).pluck(:content)).to eq(['Edited reply'])
    expect(state.reload.status).to eq('active')
    expect(state.metadata['manual_activation']).to be(true)
    expect(state.metadata['approved_draft']).to be_nil
    expect { service.send!(token: token, messages: ['Duplicate']) }.to raise_error(CustomExceptions::MarcosxAi)
  end

  it 'analyzes and sends an explicitly reviewed reply with general support disabled' do
    assistant.update!(config: assistant.resolved_config.merge(auto_response_enabled: false))
    service.start!
    token = service.report['id']
    service.perform(token)
    service.send!(token: token, messages: ['Reviewed individual reply'])
    MarcosxAi::DeliveryJob.perform_now(conversation.id, state.reload.metadata['run_token'], 0)
    expect(conversation.messages.outgoing.where(private: false).pluck(:content)).to eq(['Reviewed individual reply'])
    expect(state.reload.status).to eq('active')
    expect(assistant.reload.auto_response_enabled?).to be(false)
    expect(state.metadata['manual_activation']).to be(true)
  end

  it 'invalidates a ready reply when another message arrives' do
    service.start!
    token = service.report['id']
    service.perform(token)
    create(:message, account: account, inbox: inbox, conversation: conversation, content: 'Actually, a different question')
    expect(service.report['status']).to eq('outdated')
    expect { service.send!(token: token, messages: ['Old reply']) }.to raise_error(CustomExceptions::MarcosxAi)
    expect(conversation.messages.outgoing).to be_empty
  end

  it 'cancels approved delivery if the customer replies before the job executes' do
    service.start!
    token = service.report['id']
    service.perform(token)
    service.send!(token: token, messages: ['Old reply'])
    run = state.reload.metadata['run_token']
    create(:message, account: account, inbox: inbox, conversation: conversation, content: 'Wait')
    MarcosxAi::DeliveryJob.perform_now(conversation.id, run, 0)
    expect(conversation.messages.outgoing).to be_empty
    expect(state.reload.status).to eq('active')
  end

  it 'does not accept a reply prepared with an older agent configuration' do
    service.start!
    token = service.report['id']
    service.perform(token)
    assistant.update!(instructions: 'Changed instructions')
    expect(service.report['status']).to eq('outdated')
    expect { service.send!(token: token, messages: ['Old reply']) }.to raise_error(CustomExceptions::MarcosxAi)
  end

  it 'preserves manual activation during review and cancels an older delivery' do
    state.resume!(manual: true)
    state.update!(metadata: state.metadata.merge('run_token' => 'old', 'pending_response' => { 'messages' => ['Old reply'] }))
    service.start!
    expect(state.reload.status).to eq('active')
    expect(state.metadata['manual_activation']).to be(true)
    expect(state.current_run?('old')).to be(false)
    expect(state.metadata['pending_response']).to be_nil
    expect(conversation.messages.outgoing).to be_empty
  end

  it 'analyzes only the chosen recent messages and saves that context for continuation' do
    create(:message, account: account, inbox: inbox, conversation: conversation, content: 'New question')
    service.start!(messages_limit: 1)
    service.perform(service.report['id'])
    expect(service.report).to include('status' => 'ready', 'messages_count' => 1, 'messages_limit' => 1)
    expect(state.reload.metadata['context_messages_limit']).to eq(1)
    expect(client).to have_received(:chat) do |messages:, schema:|
      expect(messages.last[:content]).to include('New question')
      expect(messages.to_json).not_to include('Keep it short')
      expect(schema).to be_present
    end
  end

  it 'continues the next incoming message after sending a review while general support is off' do
    assistant.update!(config: assistant.resolved_config.merge(auto_response_enabled: false))
    service.start!
    token = service.report['id']
    service.perform(token)
    service.send!(token: token, messages: ['Reviewed reply'])
    MarcosxAi::DeliveryJob.perform_now(conversation.id, state.reload.metadata['run_token'], 0)
    next_message = create(:message, account: account, inbox: inbox, conversation: conversation, content: 'Another question')
    expect { MarcosxAi::ResponseScheduler.perform(message: next_message) }.to have_enqueued_job(MarcosxAi::ResponseJob)
    expect(state.reload.status).to eq('active')
    expect(state.metadata['approved_draft']).to be_nil
    expect(assistant.reload.auto_response_enabled?).to be(false)
  end

  it 'discards a provider response when the conversation changes during analysis' do
    service.start!
    token = service.report['id']
    allow(client).to receive(:chat) do
      create(:message, account: account, inbox: inbox, conversation: conversation, content: 'New detail')
      plan.to_json
    end
    service.perform(token)
    expect(service.report['status']).to eq('outdated')
    expect(conversation.messages.outgoing).to be_empty
  end

  it 'returns an outdated report after the selected agent is deleted' do
    service.start!
    token = service.report['id']
    service.perform(token)
    assistant.destroy!
    expect(described_class.new(state: state.reload).report['status']).to eq('outdated')
  end
end
