require 'rails_helper'

RSpec.describe MarcosxAi::VoicePolicy do
  let(:account) { create(:account) }
  let(:assistant) { account.marcosx_ai_assistants.create!(name: 'Support', config: { voice: { mode: 'contextual', min_text_turns: 2 } }) }
  let(:conversation) { create(:conversation, account: account) }
  let(:plan) { { messages: ['Posso conversar com você.'], reaction: nil, reaction_message_id: nil, handoff: false, handoff_reason: nil } }
  before { allow(assistant).to receive(:voice_ready?).and_return(true) }

  it 'distinguishes requests to speak from questions about audio and respects text preferences in either language' do
    expect(described_class.requested?('Pode explicar o que é um áudio?')).to be(false)
    expect(described_class.requested?('Quero saber quais tipos de áudio existem.')).to be(false)
    expect(described_class.requested?('Me manda um áudio, por favor.')).to be(true)
    expect(described_class.requested?('Fala comigo em áudio.')).to be(true)
    expect(described_class.requested?('Converse em áudio comigo.')).to be(true)
    expect(described_class.requested?("I prefer text, don't send audio.")).to be(false)
  end

  it 'recognizes requests and text preferences in cached audio transcriptions without retranscribing history' do
    create(:message, conversation: conversation, sender: assistant, message_type: :outgoing,
                     content: 'A previous reply', content_attributes: { marcosx_ai_voice_transcript: 'An earlier audio' })
    incoming = create(:message, conversation: conversation, message_type: :incoming, content: nil)
    attachment = incoming.attachments.create!(account: account, file_type: :audio,
                                              meta: { transcribed_text: 'Converse em áudio comigo, Emilly, eu não sei ler.' })
    expect(MarcosxAi::MediaContext).not_to receive(:new)
    expect(described_class.context(assistant: assistant, conversation: conversation)).to include(voice_allowed: true, voice_requested: true)
    attachment.update!(meta: { transcribed_text: 'Prefiro texto, não mande áudio.' })
    expect(described_class.context(assistant: assistant, conversation: conversation)).to include(voice_allowed: false, voice_requested: false)
  end

  it 'counts whole replies rather than split parts and respects requests and text preferences' do
    create(:message, conversation: conversation, sender: assistant, message_type: :outgoing,
                     content_attributes: { marcosx_ai_voice_transcript: 'Olá' }, additional_attributes: { trigger_message_id: 10 })
    3.times do
      create(:message, conversation: conversation, sender: assistant, message_type: :outgoing, content: 'One split reply',
                       additional_attributes: { trigger_message_id: 20 })
    end
    incoming = create(:message, conversation: conversation, message_type: :incoming, content: 'Tudo bem')
    expect(described_class.context(assistant: assistant, conversation: conversation)).to include(voice_allowed: false, text_turns_since_audio: 1)
    incoming.update!(content: 'Fala comigo em áudio, não sei ler')
    runtime = described_class.context(assistant: assistant, conversation: conversation)
    expect(runtime).to include(voice_allowed: true, voice_requested: true)
    expect(MarcosxAi::ReplyPlan.parse(plan.to_json, assistant: assistant, voice_context: runtime)['voice_text']).to eq(plan[:messages].first)
    incoming.update!(content: 'Prefiro texto, não mande áudio')
    expect(described_class.context(assistant: assistant, conversation: conversation)).to include(voice_allowed: false, voice_requested: false)
  end

  it 'allows a contextual proposal after the configured number of text turns' do
    create(:message, conversation: conversation, sender: assistant, message_type: :outgoing,
                     content_attributes: { marcosx_ai_voice_transcript: 'Olá' }, additional_attributes: { trigger_message_id: 10 })
    [20, 30].each do |trigger|
      create(:message, conversation: conversation, sender: assistant, message_type: :outgoing, content: 'Text',
                       additional_attributes: { trigger_message_id: trigger })
    end
    create(:message, conversation: conversation, message_type: :incoming, content: 'Pode explicar melhor?')
    expect(described_class.context(assistant: assistant, conversation: conversation)).to include(voice_allowed: true, voice_requested: false)
    plan[:voice_text] = 'Vou explicar.'
    denied = { voice_allowed: false, voice_requested: false }
    expect(MarcosxAi::ReplyPlan.parse(plan.to_json, assistant: assistant, voice_context: denied)['voice_text']).to be_nil
  end

  it 'limits requested mode to actual audio requests and never queries history when voice is unavailable' do
    assistant.config = { voice: { mode: 'requested' } }
    create(:message, conversation: conversation, message_type: :incoming, content: 'Oi')
    expect(described_class.context(assistant: assistant, conversation: conversation)[:voice_allowed]).to be(false)
    allow(assistant).to receive(:voice_ready?).and_return(false)
    expect(MarcosxAi::ConversationContext).not_to receive(:public_history)
    expect(described_class.context(assistant: assistant, conversation: conversation)[:voice_allowed]).to be(false)
  end
end
