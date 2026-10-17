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
    state.resume!(manual: true)
    expect(state.enabled_for_ai?).to be(true)
    expect(state.public_data[:manual_sessions_suspended]).to be(false)
    assistant.update!(config: assistant.resolved_config.merge(auto_response_enabled: false))
    expect(state.reload.enabled_for_ai?).to be(false)
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

  it 'does not repeat a delivered photo through another library entry with the same bytes' do
    photo = assistant.resources.new(account: account, title: 'Preview', description: 'A preview', kind: 'image')
    photo.file.attach(io: File.open(Rails.root.join('spec/assets/sample.png')), filename: 'photo.png', content_type: 'image/png')
    photo.save!
    duplicate = assistant.resources.new(account: account, title: 'Renamed preview', description: 'Same bytes', kind: 'image')
    duplicate.file.attach(io: File.open(Rails.root.join('spec/assets/sample.png')), filename: 'other.png', content_type: 'image/png')
    duplicate.save!
    delivered = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, sender: assistant)
    delivered.attachments.create!(account: account, file_type: 'image', file: photo.file.blob)
    instructions = MarcosxAi::ResourceCatalog.instructions(assistant, conversation: conversation)
    expect(instructions).not_to include('"title":"Preview"', '"title":"Renamed preview"')
    plan = { 'resource_ids' => [duplicate.id], 'messages' => ['Here is another photo'], 'voice_text' => 'Another photo' }
    safe = MarcosxAi::ResourceCatalog.without_repeated_media(plan, assistant, conversation)
    expect(safe['resource_ids']).to eq([])
    expect(safe['messages']).to eq([I18n.t('marcosx_ai.resource_already_sent')])
    expect(MarcosxAi::ResourceCatalog.sent_media_ids([photo], create(:conversation, account: account, inbox: inbox))).to eq([])
    delivered.update!(status: :failed)
    expect(MarcosxAi::ResourceCatalog.sent_media_ids([photo], conversation)).to eq([])
  end
end
