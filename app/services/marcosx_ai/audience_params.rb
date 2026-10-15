class MarcosxAi::AudienceParams
  def self.parse(entry, account:)
    return {} unless entry.key?(:audience)

    audience = entry[:audience]
    raise ArgumentError unless %w[global conversation contacts].include?(audience)

    ids = entry.fetch(:contact_ids, [])
    raise ArgumentError unless ids.is_a?(Array) && ids.size <= 200

    ids = ids.map do |id|
      raise ArgumentError unless id.is_a?(Integer) || (id.is_a?(String) && id.match?(/\A[1-9]\d*\z/))

      id.to_i
    end
    conversation = nil
    if audience == 'conversation'
      display_id = entry[:conversation_id]
      raise ArgumentError unless display_id.is_a?(Integer) || (display_id.is_a?(String) && display_id.match?(/\A[1-9]\d*\z/))

      conversation = account.conversations.find_by(display_id: display_id)
      raise ArgumentError unless conversation
    end
    { audience: audience, conversation: conversation, contact_ids: ids }.stringify_keys
  end
end
