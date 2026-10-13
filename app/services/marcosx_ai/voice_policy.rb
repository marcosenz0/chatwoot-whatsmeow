class MarcosxAi::VoicePolicy
  REQUESTS = [
    /(?:manda|mande|envia|envie|enviar)\s+(?:(?:pra mim|para mim|me|um|uma|o|a)\s+)*(?:áudio|audio|mensagem de voz)/i,
    /(?:fala|fale|responda|responde)\b.{0,60}(?:em|por|via|de)\s+(?:áudio|audio|voz|mensagem de voz)/i,
    /(?:quero|prefiro|preciso)(?:\s+(?:um|uma|receber|ouvir|por|em))*\s+(?:áudio|audio|mensagem de voz)/i,
    /(?:áudio|audio|mensagem de voz).{0,40}(?:por favor|pra mim|para mim)/i,
    /não sei ler|nao sei ler|dificuldade (?:para|pra|de) ler|prefiro ouvir/i,
    /(?:send|give)\s+(?:me\s+)?(?:an?\s+)?(?:audio|voice (?:message|note))/i,
    /(?:reply|speak|talk|answer).{0,40}(?:in|with|by)\s+(?:audio|voice)|(?:cannot|can't) read/i
  ].freeze
  def self.context(assistant:, conversation:)
    settings = assistant.resolved_config[:voice]
    return { voice_allowed: false, voice_requested: false, text_turns_since_audio: 0 } unless assistant.voice_ready?

    limit = (settings[:min_text_turns] + 1) * 9
    messages = MarcosxAi::ConversationContext.public_history(conversation).reorder(created_at: :desc, id: :desc).limit(limit).to_a
    incoming = messages.take_while { |message| !message.outgoing? }.select(&:incoming?).map(&:content).join(' ')
    requested = requested?(incoming)
    outgoing = messages.select { |message| message.outgoing? && message.sender_type == 'MarcosxAi::Assistant' && message.sender_id == assistant.id }
    voice_index = outgoing.index { |message| message.content_attributes['marcosx_ai_voice_transcript'].present? }
    turns = if voice_index
              voice_trigger = outgoing[voice_index].additional_attributes['trigger_message_id']
              outgoing.first(voice_index).map { |message| message.additional_attributes['trigger_message_id'] || message.id }
                      .uniq.reject { |trigger| trigger == voice_trigger }.size
            else
              settings[:min_text_turns]
            end
    allowed = requested || (settings[:mode] == 'contextual' && turns >= settings[:min_text_turns] && !declined?(incoming))
    { voice_allowed: assistant.voice_ready? && allowed, voice_requested: requested, text_turns_since_audio: turns }
  end

  def self.requested?(text)
    return false if declined?(text)

    REQUESTS.any? { |pattern| text.to_s.match?(pattern) }
  end

  def self.declined?(text)
    text.to_s.match?(/(?:não|nao) (?:me )?(?:mande|manda|envie|envia|quero).{0,20}(?:áudio|audio)|sem (?:áudio|audio)|prefiro (?:por )?texto/i) ||
      text.to_s.match?(/(?:do not|don't) (?:send|use|reply).{0,30}(?:audio|voice)|prefer text|no (?:audio|voice)/i)
  end
end
