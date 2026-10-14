require 'rails_helper'

RSpec.describe MarcosxAi::ReviewedReplyService do
  let(:account) { create(:account) }
  let!(:credential) { account.marcosx_ai_credentials.create!(provider: 'openai', api_key: 'test', enabled: true) }
  let(:assistant) { account.marcosx_ai_assistants.create!(name: 'Selected agent') }
  let(:inbox) { create(:channel_whatsmeow, account: account).inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:state) { MarcosxAi::ConversationState.for_conversation!(conversation, assistant: assistant) }
  let(:service) { described_class.new(conversation: conversation) }
  let(:bytes) { File.binread(Rails.root.join('spec/assets/sample.mp3')) }
  let(:upload) { Rack::Test::UploadedFile.new(Rails.root.join('spec/assets/sample.mp3'), 'audio/mpeg') }

  before do
    assistant.marcosx_ai_inboxes.create!(account: account, inbox: inbox)
    create(:message, conversation: conversation, account: account, inbox: inbox, content: 'Reply in audio')
    state.wait_for_human!(reason: 'Previous pause')
    allow_any_instance_of(MarcosxAi::Assistant).to receive(:voice_ready?).and_return(true)
  end

  it 'delivers the exact reviewed recording once with native voice metadata without reactivating paused AI' do
    token = service.token(snapshot: service.snapshot, audio: bytes, content: 'Reviewed words')
    expect(conversation.messages.outgoing.where(private: false)).to be_empty
    message = service.send!(token: token, content: 'Reviewed words', audio: upload)
    expect(message.sender).to eq(assistant)
    expect(message.attachments.first.file.download).to eq(bytes)
    expect(message.content_attributes).to include('whatsmeow_recorded_audio' => true, 'marcosx_ai_voice_transcript' => 'Reviewed words')
    expect(message.attachments.first.meta['transcribed_text']).to eq('Reviewed words')
    expect(state.reload.status).to eq('awaiting_human')
    expect(service.send!(token: token, content: 'Reviewed words', audio: upload).id).to eq(message.id)
    expect(conversation.messages.outgoing.where(private: false).count).to eq(1)
  end

  it 'rejects an outdated recording after a new contact message arrives' do
    token = service.token(snapshot: service.snapshot, audio: bytes, content: 'Reviewed words')
    create(:message, conversation: conversation, account: account, inbox: inbox, content: 'New request')
    expect { service.send!(token: token, content: 'Reviewed words', audio: upload) }.to raise_error(CustomExceptions::MarcosxAi)
    expect(conversation.messages.outgoing.where(private: false)).to be_empty
  end

  it 'requires regeneration after editing the transcript and rejects a different audio file' do
    token = service.token(snapshot: service.snapshot, audio: bytes, content: 'Reviewed words')
    expect { service.send!(token: token, content: 'Changed words', audio: upload) }.to raise_error(CustomExceptions::MarcosxAi)
    token = service.token(snapshot: service.snapshot, audio: 'Other recording', content: 'Reviewed words')
    expect { service.send!(token: token, content: 'Reviewed words', audio: upload) }.to raise_error(CustomExceptions::MarcosxAi)
    expect(conversation.messages.outgoing.where(private: false)).to be_empty
  end

  it 'rejects another conversation and expired tokens while permitting edited text after review' do
    token = service.token(snapshot: service.snapshot)
    other = create(:conversation, account: account, inbox: inbox)
    expect { described_class.new(conversation: other).send!(token: token, content: 'Wrong recipient') }.to raise_error(CustomExceptions::MarcosxAi)
    travel 31.minutes do
      expect { service.send!(token: token, content: 'Expired') }.to raise_error(CustomExceptions::MarcosxAi)
    end
    expect(service.send!(token: token, content: 'Edited reply').content).to eq('Edited reply')
  end
end
