require 'rails_helper'

RSpec.describe 'MarcoXIA conversation runtime' do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let!(:credential) { account.marcosx_ai_credentials.create!(provider: 'openai', api_key: 'test', enabled: true) }
  let!(:assistant) {
    account.marcosx_ai_assistants.create!(name: 'Support', instructions: 'Never invent prices', config: { auto_response_enabled: true })
  }
  let(:inbox) { create(:channel_whatsmeow, account: account).inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:message) { create(:message, account: account, inbox: inbox, conversation: conversation, sender: conversation.contact, content: 'Hello') }
  let(:state) { MarcosxAi::ConversationState.for_conversation!(conversation, assistant: assistant) }
  let(:client) { instance_double(MarcosxAi::ProviderClient, usage: {}) }
  let(:plan) { { messages: ['Hello', 'How can I help?'], reaction: nil, reaction_message_id: nil, handoff: false, handoff_reason: nil } }

  before do
    allow(Whatsmeow::TypingStatusService).to receive(:new).and_return(instance_double(Whatsmeow::TypingStatusService, perform: nil))
    assistant.marcosx_ai_inboxes.create!(account: account, inbox: inbox)
    allow(MarcosxAi::ProviderClient).to receive(:new).and_return(client)
    allow(client).to receive(:chat) { plan.to_json }
    message
    clear_enqueued_jobs
  end

  it 'debounces a burst and makes the earlier job obsolete' do
    MarcosxAi::ResponseScheduler.perform(message: message)
    first = state.reload.metadata['run_token']
    next_message = create(:message, account: account, conversation: conversation, inbox: inbox, sender: conversation.contact,
                                    content: 'Another detail')
    MarcosxAi::ResponseScheduler.perform(message: next_message)
    expect(state.reload.metadata['run_token']).not_to eq(first)
    expect(state.metadata['pending_since_message_id']).to eq(message.id)
    MarcosxAi::ResponseJob.perform_now(conversation.id, assistant.id, message.id, first)
    expect(client).not_to have_received(:chat)
  end

  it 'does not automatically start in manual mode' do
    assistant.update!(config: assistant.resolved_config.merge(auto_start: false))
    inbox.reload
    new_conversation = create(:conversation, account: account, inbox: inbox)
    incoming = create(:message, account: account, inbox: inbox, conversation: new_conversation)
    expect { MarcosxAi::ResponseScheduler.perform(message: incoming) }.not_to have_enqueued_job(MarcosxAi::ResponseJob)
    expect(MarcosxAi::ConversationState.find_by!(conversation: new_conversation).status).to eq('paused_by_agent')
    expect(inbox.external_bot_active?).to be(false)
  end

  it 'does not restart an explicitly paused agent when another customer message arrives' do
    state.pause_by_agent!
    expect { MarcosxAi::ResponseScheduler.perform(message: message) }.not_to have_enqueued_job(MarcosxAi::ResponseJob)
  end

  it 'responds in a manually enabled conversation while general support is off without enabling another contact' do
    assistant.update!(config: assistant.resolved_config.merge(auto_response_enabled: false))
    state.resume!(manual: true)
    MarcosxAi::ResponseScheduler.perform(message: message)
    token = state.reload.metadata['run_token']
    MarcosxAi::ResponseJob.perform_now(conversation.id, assistant.id, message.id, token)
    MarcosxAi::DeliveryJob.perform_now(conversation.id, token, 0)
    MarcosxAi::DeliveryJob.perform_now(conversation.id, token, 1)
    expect(conversation.messages.outgoing.where(private: false).order(:id).pluck(:content)).to eq(plan[:messages])
    expect(state.public_data).to include(enabled: true, available: true, manual_activation: true)
    expect(assistant.reload.auto_response_enabled?).to be(false)

    other = create(:conversation, account: account, inbox: inbox)
    expect {
      incoming = create(:message, account: account, inbox: inbox, conversation: other)
      MarcosxAi::ResponseScheduler.perform(message: incoming)
    }.not_to have_enqueued_job(MarcosxAi::ResponseJob)
  end

  it 'stops an automatic pending reply when general support is disabled' do
    MarcosxAi::ResponseScheduler.perform(message: message)
    token = state.reload.metadata['run_token']
    assistant.update!(config: assistant.resolved_config.merge(auto_response_enabled: false))
    MarcosxAi::ResponseJob.perform_now(conversation.id, assistant.id, message.id, token)
    expect(client).not_to have_received(:chat)
    expect { MarcosxAi::ResponseScheduler.perform(message: message) }.not_to have_enqueued_job(MarcosxAi::ResponseJob)
  end

  it 'stops a pending individually enabled reply when that conversation is paused' do
    assistant.update!(config: assistant.resolved_config.merge(auto_response_enabled: false))
    state.resume!(manual: true)
    MarcosxAi::ResponseScheduler.perform(message: message)
    token = state.reload.metadata['run_token']
    state.pause_by_agent!
    MarcosxAi::ResponseJob.perform_now(conversation.id, assistant.id, message.id, token)
    expect(client).not_to have_received(:chat)
    expect { MarcosxAi::ResponseScheduler.perform(message: message) }.not_to have_enqueued_job(MarcosxAi::ResponseJob)
  end

  it 'does not deliver a manual reply after the provider connection is disabled' do
    assistant.update!(config: assistant.resolved_config.merge(auto_response_enabled: false))
    state.resume!(manual: true)
    MarcosxAi::ResponseScheduler.perform(message: message)
    token = state.reload.metadata['run_token']
    MarcosxAi::ResponseJob.perform_now(conversation.id, assistant.id, message.id, token)
    credential.update!(enabled: false)
    MarcosxAi::DeliveryJob.perform_now(conversation.id, token, 0)
    expect(conversation.messages.outgoing.where(private: false)).to be_empty
    expect(state.public_data[:available]).to be(false)
  end

  it 'never times out a permanent human takeover' do
    state.pause_by_human!(message: message, minutes: 0)
    travel 2.days do
      expect(state.active_for_ai?).to be(false)
    end
  end

  it 'can resume a configured temporary human pause' do
    state.pause_by_human!(message: message, minutes: 15)
    travel 16.minutes do
      expect(state.active_for_ai?).to be(true)
    end
  end

  it 'pauses when a human replies and invalidates an in-flight response' do
    MarcosxAi::ResponseScheduler.perform(message: message)
    token = state.reload.metadata['run_token']
    reply = create(:message, account: account, conversation: conversation, inbox: inbox, message_type: :outgoing)
    event = Events::Base.new('message.created', Time.current, message: reply)
    MarcosxAiListener.instance.message_created(event)
    expect(state.reload.status).to eq('paused_by_human')
    expect(state.current_run?(token)).to be(false)
  end

  it 'does not pause on a private human note' do
    reply = create(:message, account: account, conversation: conversation, inbox: inbox, message_type: :outgoing, private: true)
    MarcosxAiListener.instance.message_created(Events::Base.new('message.created', Time.current, message: reply))
    expect(state.reload.status).to eq('active')
  end

  it 'ignores historical imports, deleted messages and groups by default' do
    message.update!(content_attributes: { historical: true })
    expect { MarcosxAi::ResponseScheduler.perform(message: message) }.not_to have_enqueued_job(MarcosxAi::ResponseJob)
    message.update!(content_attributes: { deleted: true })
    expect { MarcosxAi::ResponseScheduler.perform(message: message) }.not_to have_enqueued_job(MarcosxAi::ResponseJob)
    message.update!(content_attributes: {})
    conversation.update!(additional_attributes: { whatsmeow_group: true })
    expect { MarcosxAi::ResponseScheduler.perform(message: message) }.not_to have_enqueued_job(MarcosxAi::ResponseJob)
  end

  it 'cancels generation if an operator takes over while the provider is responding' do
    MarcosxAi::ResponseScheduler.perform(message: message)
    token = state.reload.metadata['run_token']
    allow(client).to receive(:chat) do
      state.pause_by_agent!
      plan.to_json
    end
    expect { MarcosxAi::ResponseJob.perform_now(conversation.id, assistant.id, message.id, token) }.not_to have_enqueued_job(MarcosxAi::DeliveryJob)
  end

  it 'delivers parts separately and suppresses duplicate delivery jobs' do
    MarcosxAi::ResponseScheduler.perform(message: message)
    token = state.reload.metadata['run_token']
    MarcosxAi::ResponseJob.perform_now(conversation.id, assistant.id, message.id, token)
    MarcosxAi::DeliveryJob.perform_now(conversation.id, token, 0)
    MarcosxAi::DeliveryJob.perform_now(conversation.id, token, 0)
    expect(conversation.messages.outgoing.where(private: false).pluck(:content)).to eq(['Hello'])
    MarcosxAi::DeliveryJob.perform_now(conversation.id, token, 1)
    expect(conversation.messages.outgoing.where(private: false).order(:id).pluck(:content)).to eq(plan[:messages])
    expect(state.reload.metadata['processing']).to be(false)
  end

  it 'stops the remaining parts when a new incoming message arrives' do
    MarcosxAi::ResponseScheduler.perform(message: message)
    token = state.reload.metadata['run_token']
    MarcosxAi::ResponseJob.perform_now(conversation.id, assistant.id, message.id, token)
    MarcosxAi::DeliveryJob.perform_now(conversation.id, token, 0)
    next_message = create(:message, account: account, conversation: conversation, inbox: inbox, sender: conversation.contact)
    MarcosxAi::ResponseScheduler.perform(message: next_message)
    MarcosxAi::DeliveryJob.perform_now(conversation.id, token, 1)
    expect(conversation.messages.outgoing.where(private: false).count).to eq(1)
  end

  it 'cancels a pending response when its agent configuration changes' do
    MarcosxAi::ResponseScheduler.perform(message: message)
    token = state.reload.metadata['run_token']
    assistant.update!(instructions: 'Updated instructions')
    expect(state.reload.current_run?(token)).to be(false)
    expect(state.metadata['processing']).to be(false)
  end

  it 'sends a contextual reaction using the existing WhatsApp provider' do
    message.update!(source_id: 'whatsapp-id')
    plan.merge!(messages: [], reaction: '👍', reaction_message_id: message.id)
    reaction = instance_double(Whatsmeow::ReactionService, perform: message)
    allow(Whatsmeow::ReactionService).to receive(:new).with(message: message, emoji: '👍', actor: assistant).and_return(reaction)
    MarcosxAi::ResponseScheduler.perform(message: message)
    token = state.reload.metadata['run_token']
    MarcosxAi::ResponseJob.perform_now(conversation.id, assistant.id, message.id, token)
    MarcosxAi::DeliveryJob.perform_now(conversation.id, token, 0)
    expect(reaction).to have_received(:perform).once
    expect(conversation.messages.outgoing.where(private: false)).to be_empty
  end

  it 'hands off to a human and stops automatic responses' do
    plan.merge!(messages: ['I will ask a colleague'], handoff: true, handoff_reason: 'Customer asked for a person')
    MarcosxAi::ResponseScheduler.perform(message: message)
    token = state.reload.metadata['run_token']
    MarcosxAi::ResponseJob.perform_now(conversation.id, assistant.id, message.id, token)
    MarcosxAi::DeliveryJob.perform_now(conversation.id, token, 0)
    expect(state.reload.status).to eq('handoff')
    expect { MarcosxAi::ResponseScheduler.perform(message: message) }.not_to have_enqueued_job(MarcosxAi::ResponseJob)
  end

  it 'keeps a provider failure internal and pauses instead of replying with a technical error' do
    allow(client).to receive(:chat).and_raise(CustomExceptions::MarcosxAi, 'Provider unavailable')
    MarcosxAi::ResponseScheduler.perform(message: message)
    token = state.reload.metadata['run_token']
    MarcosxAi::ResponseJob.perform_now(conversation.id, assistant.id, message.id, token)
    expect(state.reload.status).to eq('error')
    expect(conversation.messages.outgoing.where(private: false)).to be_empty
    expect(conversation.messages.outgoing.where(private: true).last.content).to include('Provider unavailable')
  end

  it 'keeps manual support active after suggesting a handoff and responds to the next incoming question' do
    assistant.update!(config: assistant.resolved_config.merge(auto_response_enabled: false))
    state.resume!(manual: true)
    plan.merge!(messages: ['I will ask a colleague'], handoff: true, handoff_reason: 'Needs an external action')
    MarcosxAi::ResponseScheduler.perform(message: message)
    token = state.reload.metadata['run_token']
    MarcosxAi::ResponseJob.perform_now(conversation.id, assistant.id, message.id, token)
    MarcosxAi::DeliveryJob.perform_now(conversation.id, token, 0)
    expect(state.reload.status).to eq('active')
    expect(conversation.messages.outgoing.where(private: true).last.content).to include('Needs an external action')
    next_message = create(:message, account: account, inbox: inbox, conversation: conversation, sender: conversation.contact)
    expect { MarcosxAi::ResponseScheduler.perform(message: next_message) }.to have_enqueued_job(MarcosxAi::ResponseJob)
  end
end
