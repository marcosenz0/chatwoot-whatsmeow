require 'rails_helper'

RSpec.describe 'MarcoXIA current contact format' do
  let(:account) { create(:account) }
  let(:assistant) { account.marcosx_ai_assistants.create!(name: 'Support', config: { voice: { mode: 'contextual', min_text_turns: 6 } }) }
  let(:conversation) { create(:conversation, account: account) }
  let(:plan) { { messages: ['Posso conversar com você.'], voice_text: nil, reaction: nil,
                reaction_message_id: nil, handoff: false, handoff_reason: nil } }
  before { allow(assistant).to receive(:voice_ready?).and_return(true) }

  def incoming(text = nil, audio: false, **attributes)
    message = create(:message, conversation: conversation, message_type: :incoming, content: text, **attributes)
    message.attachments.create!(account: account, file_type: :audio) if audio
    message
  end

  def runtime
    MarcosxAi::VoicePolicy.context(assistant: assistant, conversation: conversation)
  end

  it 'follows audio, text, audio and text immediately without a spacing interval or an intervening reply' do
    [true, false, true, false].each do |audio|
      incoming(audio ? nil : 'Como você está?', audio: audio)
      expect(runtime).to include(voice_allowed: audio, voice_requested: audio, latest_contact_medium: audio ? 'audio' : 'text')
    end
  end

  it 'lets a current explicit audio request override the text format for that turn only' do
    incoming('Me manda um áudio por favor')
    expect(runtime).to include(voice_allowed: true, latest_contact_medium: 'text')
    incoming('Esse nome é qual?')
    expect(runtime).to include(voice_allowed: false, voice_requested: false)
  end

  it 'uses a cached current audio transcription for a text request without retranscribing history' do
    message = incoming(nil, audio: true)
    message.attachments.first.update!(meta: { transcribed_text: 'Prefiro texto, não mande áudio.' })
    expect(MarcosxAi::MediaContext).not_to receive(:new)
    expect(runtime).to include(voice_allowed: false, latest_contact_medium: 'audio')
    incoming(nil, audio: true)
    expect(runtime).to include(voice_allowed: true, voice_requested: true)
  end

  it 'supplies an audio alternative for received audio and preserves links in text' do
    incoming(nil, audio: true)
    plan[:messages] << 'Abra https://example.invalid'
    result = MarcosxAi::ReplyPlan.parse(plan.to_json, assistant: assistant, voice_context: runtime)
    expect(result['voice_text']).to eq(plan[:messages].first)
    expect(result['messages']).to include('Abra https://example.invalid')
    incoming('Boa tarde')
    plan[:voice_text] = 'O modelo ainda quer falar'
    expect(MarcosxAi::ReplyPlan.parse(plan.to_json, assistant: assistant, voice_context: runtime)['voice_text']).to be_nil
  end

  it 'ignores private, deleted and outgoing audio when selecting the current format' do
    incoming('Boa tarde')
    incoming(nil, audio: true, private: true)
    incoming(nil, audio: true, content_attributes: { deleted: true })
    create(:message, conversation: conversation, sender: assistant, message_type: :outgoing,
                     content_attributes: { marcosx_ai_voice_transcript: 'Uma resposta anterior' })
    expect(runtime).to include(voice_allowed: false, latest_contact_medium: 'text')
  end

  it 'finds incoming audio beyond a burst of outgoing parts' do
    incoming(nil, audio: true)
    create_list(:message, 65, conversation: conversation, message_type: :outgoing, sender: assistant)
    expect(runtime).to include(voice_allowed: true, latest_contact_medium: 'audio')
  end

  it 'orders incoming messages by timestamp and breaks ties by ID' do
    at = Time.current
    incoming(nil, audio: true, created_at: at)
    incoming('Agora por texto', created_at: at)
    incoming(nil, audio: true, created_at: 1.day.ago)
    expect(runtime).to include(voice_allowed: false, latest_contact_medium: 'text')
  end

  it 'keeps requested-only mode explicit without inheriting an old request' do
    assistant.config = { voice: { mode: 'requested' } }
    incoming(nil, audio: true)
    expect(runtime[:voice_allowed]).to be(false)
    incoming('Manda um áudio')
    expect(runtime[:voice_allowed]).to be(true)
    incoming('Oi')
    expect(runtime[:voice_allowed]).to be(false)
  end

  it 'defaults to text when there is no incoming contact message' do
    expect(runtime).to include(voice_allowed: false, voice_requested: false)
  end
end
