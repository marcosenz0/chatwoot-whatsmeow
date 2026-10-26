require 'rails_helper'

RSpec.describe 'MarcoXIA activation and media continuity' do
  include ActiveJob::TestHelper
  let(:account) { create(:account) }
  let!(:credential) { account.marcosx_ai_credentials.create!(provider: 'openai', api_key: 'test', enabled: true) }
  let(:assistant) { account.marcosx_ai_assistants.create!(name: 'Support', config: { auto_response_enabled: true, manual_sessions_enabled: false }) }
  let(:inbox) { create(:channel_whatsmeow, account: account).inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:state) { MarcosxAi::ConversationState.for_conversation!(conversation, assistant: assistant) }
  before do
    assistant.marcosx_ai_inboxes.create!(account: account, inbox: inbox)
    allow(Whatsmeow::TypingStatusService).to receive(:new).and_return(instance_double(Whatsmeow::TypingStatusService, perform: nil))
  end

  it 'shows global coverage before the first incoming message without creating state' do
    expect { expect(conversation.marcosx_ai_state_data).to include(status: 'active', enabled: true, assistant_id: assistant.id) }
      .not_to change(MarcosxAi::ConversationState, :count)
    assistant.update!(config: assistant.resolved_config.merge(auto_response_enabled: false))
    expect(conversation.reload.marcosx_ai_state_data[:enabled]).to be(false)
  end

  it 'lets general support cover manual members even when manual-only attendance is suspended' do
    state.update!(metadata: { manual_activation: true })
    expect(state.enabled_for_ai?).to be(true)
    expect(state.public_data[:manual_sessions_suspended]).to be(false)
    assistant.update!(config: assistant.resolved_config.merge(auto_response_enabled: false))
    expect(state.reload.enabled_for_ai?).to be(false)
    state.resume!(manual: true)
    expect(state.enabled_for_ai?).to be(true)
    expect(state.public_data[:manual_sessions_suspended]).to be(false)
  end

  it 'recovers old zero-minute human pauses but preserves explicit pauses and human assistance' do
    state.update!(status: 'paused_by_human', metadata: { paused_reason: 'human_response' })
    expect(state.public_data[:status]).to eq('active')
    expect(state.active_for_ai?).to be(true)
    state.pause_by_agent!
    expect(state.active_for_ai?).to be(false)
    state.wait_for_human!(reason: 'Payment verification')
    expect(state.active_for_ai?).to be(false)
  end

  it 'cancels a current run after a human reply without disabling subsequent automatic replies' do
    incoming = create(:message, account: account, inbox: inbox, conversation: conversation)
    MarcosxAi::ResponseScheduler.perform(message: incoming)
    token = state.reload.metadata['run_token']
    human = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing)
    state.pause_by_human!(message: human, minutes: 0)
    expect(state.reload.status).to eq('active')
    expect(state.current_run?(token)).to be(false)
    next_incoming = create(:message, account: account, inbox: inbox, conversation: conversation)
    expect { MarcosxAi::ResponseScheduler.perform(message: next_incoming) }.to have_enqueued_job(MarcosxAi::ResponseJob)
  end

  it 'keeps sent media available, shares history between renamed copies, and distinguishes failed attempts' do
    photo = assistant.resources.new(account: account, title: 'Preview', description: 'Send when asked for a preview', kind: 'image')
    photo.file.attach(io: File.open(Rails.root.join('spec/assets/sample.png')), filename: 'photo.png', content_type: 'image/png')
    photo.save!
    duplicate = assistant.resources.new(account: account, title: 'Renamed preview', description: 'Same bytes', kind: 'image')
    duplicate.file.attach(photo.file.blob)
    duplicate.save!
    delivered = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                                 sender: assistant, status: :delivered, created_at: 3.weeks.ago)
    delivered.attachments.create!(account: account, file_type: 'image', file: photo.file.blob)
    instructions = MarcosxAi::ResourceCatalog.instructions(assistant, conversation: conversation)
    expect(instructions).to include('"title":"Preview"', '"title":"Renamed preview"', '"sent_count":1', '"confirmed_count":1')
    expect(instructions).to include('reenviar', 'sent_count=0')
    follow_up = create(:conversation, account: account, inbox: inbox, contact: conversation.contact)
    history = MarcosxAi::ResourceHistory.for([photo, duplicate], follow_up)
    expect(history[photo.id]).to include(sent_count: 1, confirmed_count: 1, failed_count: 0, last_message_id: delivered.id)
    expect(history[duplicate.id]).to eq(history[photo.id])
    delivered.update!(status: :failed)
    expect(MarcosxAi::ResourceHistory.for([photo], follow_up)[photo.id]).to include(sent_count: 0, confirmed_count: 0, failed_count: 1)
  end

  it 'respects contact, inbox, forgotten and excluded history boundaries' do
    photo = assistant.resources.new(account: account, title: 'Preview', description: 'A preview', kind: 'image')
    photo.file.attach(io: File.open(Rails.root.join('spec/assets/sample.png')), filename: 'photo.png', content_type: 'image/png')
    photo.save!
    delivered = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, sender: assistant)
    delivered.attachments.create!(account: account, file_type: 'image', file: photo.file.blob)
    stranger = create(:conversation, account: account, inbox: inbox)
    expect(MarcosxAi::ResourceHistory.for([photo], stranger)[photo.id][:sent_count]).to eq(0)
    other_inbox = create(:channel_whatsmeow, account: account).inbox
    other_channel = create(:conversation, account: account, inbox: other_inbox, contact: conversation.contact)
    expect(MarcosxAi::ResourceHistory.for([photo], other_channel)[photo.id][:sent_count]).to eq(0)
    memory = MarcosxAi::ContactMemory.create!(account: account, contact: conversation.contact)
    memory.exclude!(delivered)
    expect(MarcosxAi::ResourceHistory.for([photo], conversation)[photo.id][:sent_count]).to eq(0)
    memory.exclude!(delivered, restore: true)
    expect(MarcosxAi::ResourceHistory.for([photo], conversation)[photo.id][:sent_count]).to eq(1)
    memory.forget!
    expect(MarcosxAi::ResourceHistory.for([photo], conversation)[photo.id][:sent_count]).to eq(0)
  end

  it 'can resend the requested photo in a new turn, records its description, and still prevents duplicate delivery of one run' do
    photo = assistant.resources.new(account: account, title: 'Reference photo', description: 'Send when the person asks for this photo', kind: 'image')
    photo.file.attach(io: File.open(Rails.root.join('spec/assets/sample.png')), filename: 'photo.png', content_type: 'image/png')
    photo.save!
    client = instance_double(MarcosxAi::ProviderClient, usage: {})
    allow(MarcosxAi::ProviderClient).to receive(:new).and_return(client)
    allow(client).to receive(:chat).and_return({ messages: [], resource_ids: [photo.id], reaction: nil, reaction_message_id: nil,
                                               handoff: false, handoff_reason: nil }.to_json)
    ['Send this photo', 'I lost it, please resend the same photo'].each do |request|
      incoming = create(:message, account: account, inbox: inbox, conversation: conversation, sender: conversation.contact, content: request)
      MarcosxAi::ResponseScheduler.perform(message: incoming)
      token = state.reload.metadata['run_token']
      MarcosxAi::ConversationResponderService.new(conversation: conversation, assistant: assistant, trigger_message: incoming, token: token).perform
      2.times { MarcosxAi::DeliveryJob.perform_now(conversation.id, token, 0) }
    end
    sent = conversation.messages.outgoing.where(private: false).order(:id)
    expect(sent.count).to eq(2)
    expect(sent.map { |message| message.attachments.first.file.blob }).to all(eq(photo.file.blob))
    expect(sent.last.additional_attributes['marcosx_ai_resource']).to include('title' => photo.title, 'description' => photo.description)
    expect(MarcosxAi::ResourceHistory.for([photo], conversation)[photo.id][:sent_count]).to eq(2)
  end
end
