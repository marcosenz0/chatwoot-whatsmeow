require 'rails_helper'

RSpec.describe 'MarcoXIA native Pix delivery' do
  include ActiveJob::TestHelper
  let(:account) { create(:account) }
  let!(:credential) { account.marcosx_ai_credentials.create!(provider: 'openai', api_key: 'test', enabled: true) }
  let!(:assistant) { account.marcosx_ai_assistants.create!(name: 'Support', config: { auto_response_enabled: true }) }
  let(:inbox) { create(:channel_whatsmeow, account: account).inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:message) { create(:message, account: account, inbox: inbox, conversation: conversation, sender: conversation.contact, content: 'Send your Pix') }
  let(:state) { MarcosxAi::ConversationState.for_conversation!(conversation, assistant: assistant) }
  let!(:key) { assistant.pix_keys.create!(account: account, title: 'Main', key_type: 'EMAIL', key: 'test@example.com', merchant_name: 'Test holder', position: 1) }
  let(:plan) { { messages: ['Here is the Pix card'], reaction: nil, reaction_message_id: nil, handoff: false, handoff_reason: nil, pix_key_id: key.id } }
  let(:client) { instance_double(MarcosxAi::ProviderClient, usage: {}) }

  before do
    assistant.marcosx_ai_inboxes.create!(account: account, inbox: inbox)
    allow(Whatsmeow::TypingStatusService).to receive(:new).and_return(instance_double(Whatsmeow::TypingStatusService, perform: nil))
    allow(MarcosxAi::ProviderClient).to receive(:new).and_return(client)
    allow(client).to receive(:chat).and_return(plan.to_json)
  end

  it 'sends the registered native card after text and resources, attributes the agent and never rewrites the inbox key' do
    resource = assistant.resources.create!(account: account, title: 'Table', description: 'Prices', kind: 'link', url: 'https://example.com/table')
    plan[:resource_ids] = [resource.id]
    channel_key = inbox.channel.attributes.slice('pix_key', 'pix_key_type', 'pix_merchant_name')
    MarcosxAi::ResponseScheduler.perform(message: message)
    token = state.reload.metadata['run_token']
    expect(MarcosxAi::ConversationResponderService.new(conversation: conversation, assistant: assistant, trigger_message: message, token: token).perform).to be_present
    3.times { |index| MarcosxAi::DeliveryJob.perform_now(conversation.id, token, index) }
    outgoing = conversation.messages.outgoing.where(private: false).order(:id)
    expect(outgoing.map(&:content)).to eq(['Here is the Pix card', resource.url, key.merchant_name])
    expect(outgoing.last.content_attributes['whatsmeow_pix']).to eq(key.payload.to_h.stringify_keys)
    expect(outgoing.last.additional_attributes).to include('marcosx_ai' => true, 'marcosx_ai_pix_key_id' => key.id)
    expect(outgoing.map(&:sender)).to all(eq(assistant))
    expect(inbox.channel.reload.attributes.slice('pix_key', 'pix_key_type', 'pix_merchant_name')).to eq(channel_key)
    MarcosxAi::DeliveryJob.perform_now(conversation.id, token, 2)
    expect(conversation.messages.outgoing.count).to eq(3)
    expect(state.reload.metadata['processing']).to be(false)
  end

  it 'does not send a revoked key while delivery waits between message parts' do
    MarcosxAi::ResponseScheduler.perform(message: message)
    token = state.reload.metadata['run_token']
    MarcosxAi::ConversationResponderService.new(conversation: conversation, assistant: assistant, trigger_message: message, token: token).perform
    MarcosxAi::DeliveryJob.perform_now(conversation.id, token, 0)
    key.update!(position: nil)
    MarcosxAi::DeliveryJob.perform_now(conversation.id, token, 1)
    expect(conversation.messages.outgoing.count).to eq(1)
    expect(state.reload.metadata['processing']).to be(false)
  end

  it 'removes Pix from acknowledgement-only human handoffs' do
    assistant.update!(config: assistant.resolved_config.merge(pause_on_handoff: true, pause_acknowledgement: true))
    plan.merge!(handoff: true, handoff_reason: 'Verify payment with the owner')
    MarcosxAi::ResponseScheduler.perform(message: message)
    token = state.reload.metadata['run_token']
    response = MarcosxAi::ConversationResponderService.new(conversation: conversation, assistant: assistant, trigger_message: message, token: token).perform
    expect(response['pix_key_id']).to be_nil
    MarcosxAi::DeliveryJob.perform_now(conversation.id, token, 0)
    expect(conversation.messages.outgoing.where(private: false).count).to eq(1)
    expect(conversation.messages.outgoing.where(private: false).last.content_attributes['whatsmeow_pix']).to be_nil
  end
end
