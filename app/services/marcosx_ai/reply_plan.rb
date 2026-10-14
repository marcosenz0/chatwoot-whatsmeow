class MarcosxAi::ReplyPlan
  REACTIONS = ['👍', '❤️', '😊', '🙏', '👏', '🎉'].freeze
  SCHEMA = {
    type: 'object', additionalProperties: false,
    properties: {
      messages: { type: 'array', items: { type: 'string' } },
      voice_text: { type: ['string', 'null'] },
      pix_key_id: { type: ['integer', 'null'] },
      resource_ids: { type: 'array', maxItems: 3, items: { type: 'integer' } },
      reaction: { type: ['string', 'null'], enum: [*REACTIONS, nil] },
      reaction_message_id: { type: ['integer', 'null'] },
      handoff: { type: 'boolean' },
      handoff_reason: { type: ['string', 'null'] },
      alert_rule_ids: { type: 'array', items: { type: 'string' } },
      recall_context: { type: 'boolean' }
    },
    required: %w[messages voice_text resource_ids pix_key_id reaction reaction_message_id handoff handoff_reason alert_rule_ids recall_context]
  }.freeze

  def self.parse(text, assistant:, recent_messages: [], voice_context: nil, pix_available: true)
    plan = JSON.parse(text)
    plan = { 'alert_rule_ids' => [], 'recall_context' => false, 'voice_text' => nil, 'resource_ids' => [], 'pix_key_id' => nil }.merge(plan) if plan.is_a?(Hash)
    unless plan.is_a?(Hash) && plan['messages'].is_a?(Array) && plan['messages'].all? { |part| part.is_a?(String) } &&
           [true, false].include?(plan['handoff']) && SCHEMA[:required].all? { |key| plan.key?(key) } &&
           [*REACTIONS, nil].include?(plan['reaction']) && (plan['reaction_message_id'].nil? || plan['reaction_message_id'].is_a?(Integer)) &&
           (plan['handoff_reason'].nil? || plan['handoff_reason'].is_a?(String)) &&
           plan['alert_rule_ids'].is_a?(Array) && plan['alert_rule_ids'].all? { |id| id.is_a?(String) } &&
           [true, false].include?(plan['recall_context'])
      raise CustomExceptions::MarcosxAi, I18n.t('marcosx_ai.errors.invalid_response')
    end

    if !pix_available && plan['pix_key_id'].present?
      raise CustomExceptions::MarcosxAi, I18n.t('marcosx_ai.errors.invalid_response')
    end
    MarcosxAi::PixCatalog.validate!(plan['pix_key_id'], assistant)
    MarcosxAi::ResourceCatalog.validate!(plan['resource_ids'], assistant)
    parts = MarcosxAi::ReplyStyle.apply(plan['messages'].map(&:strip).compact_blank,
                                        assistant: assistant, recent_messages: recent_messages)
    limit = assistant.split_messages? ? assistant.max_message_parts : 1
    parts = natural_parts(parts, assistant: assistant) if assistant.split_messages? && limit > 1
    parts = [*parts.first(limit - 1), parts.drop(limit - 1).join("\n\n")] if parts.size > limit
    voice = plan['voice_text']
    unless voice.nil? || (voice.is_a?(String) && voice.length <= assistant.resolved_config.dig(:voice, :max_characters))
      raise CustomExceptions::MarcosxAi, I18n.t('marcosx_ai.errors.invalid_response')
    end

    if voice_context && !plan['handoff']
      voice = nil unless voice_context[:voice_allowed]
      if voice_context[:voice_allowed] && voice_context[:voice_requested] && voice.blank?
        spoken = parts.reject { |part| part.match?(%r{https?://|www\.}i) }.join(' ')
        voice = spoken if spoken.length <= assistant.resolved_config.dig(:voice, :max_characters)
      end
    end
    plan.merge('messages' => parts, 'voice_text' => assistant.voice_ready? ? voice&.strip.presence : nil)
  rescue JSON::ParserError
    raise CustomExceptions::MarcosxAi, I18n.t('marcosx_ai.errors.invalid_response')
  end

  def self.natural_parts(parts, assistant:)
    parts.flat_map do |part|
      part.split(/\n\s*\n/).flat_map do |paragraph|
        next [paragraph] if paragraph.include?("\n")

        sentences = paragraph.split(/(?<=[.!?])\s+(?=[\p{L}¿¡\p{Extended_Pictographic}])/u)
        complete = sentences.each_with_object([]) do |sentence, result|
          previous = result.last
          if previous && (previous.match?(/\b(?:Dr|Dra|Sr|Sra|Mr|Mrs|Ms|Prof|Av|etc)\.$/i) ||
                          previous.split.last.match?(%r{(?:https?://|www\.)}))
            result[-1] = "#{previous} #{sentence}"
          else
            result << sentence
          end
        end
        target = assistant.resolved_config[:message_target_characters]
        complete.each_with_object([]) do |sentence, result|
          previous = result.last
          greeting = assistant.resolved_config[:separate_greeting] &&
                     previous&.match?(/\A(?:oi(?:e*)|ol[aá]|bom dia|boa tarde|boa noite|hello|hi|hey)\b/i)
          if previous && !greeting && previous.length + sentence.length + 1 <= target
            result[-1] = "#{previous} #{sentence}"
          else
            result << sentence
          end
        end
      end
    end
  end
end
