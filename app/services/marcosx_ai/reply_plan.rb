class MarcosxAi::ReplyPlan
  REACTIONS = ['👍', '❤️', '😊', '🙏', '👏', '🎉'].freeze
  SCHEMA = {
    type: 'object', additionalProperties: false,
    properties: {
      messages: { type: 'array', items: { type: 'string' } },
      reaction: { type: ['string', 'null'], enum: [*REACTIONS, nil] },
      reaction_message_id: { type: ['integer', 'null'] },
      handoff: { type: 'boolean' },
      handoff_reason: { type: ['string', 'null'] }
    },
    required: %w[messages reaction reaction_message_id handoff handoff_reason]
  }.freeze

  def self.parse(text, assistant:)
    plan = JSON.parse(text)
    unless plan.is_a?(Hash) && plan['messages'].is_a?(Array) && plan['messages'].all? { |part| part.is_a?(String) } &&
           [true, false].include?(plan['handoff']) && SCHEMA[:required].all? { |key| plan.key?(key) } &&
           [*REACTIONS, nil].include?(plan['reaction']) && (plan['reaction_message_id'].nil? || plan['reaction_message_id'].is_a?(Integer)) &&
           (plan['handoff_reason'].nil? || plan['handoff_reason'].is_a?(String))
      raise CustomExceptions::MarcosxAi, I18n.t('marcosx_ai.errors.invalid_response')
    end

    parts = plan['messages'].map(&:strip).compact_blank
    limit = assistant.split_messages? ? assistant.max_message_parts : 1
    parts = [*parts.first(limit - 1), parts.drop(limit - 1).join("\n\n")] if parts.size > limit
    plan.merge('messages' => parts)
  rescue JSON::ParserError
    raise CustomExceptions::MarcosxAi, I18n.t('marcosx_ai.errors.invalid_response')
  end
end
