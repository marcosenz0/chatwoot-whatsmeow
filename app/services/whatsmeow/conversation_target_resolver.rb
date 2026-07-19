class Whatsmeow::ConversationTargetResolver
  pattr_initialize [:conversation!]

  def perform
    target = normalized_jid(source_id) || normalized_phone_jid(source_id)
    raise invalid_target_error if target.blank?

    log_contact_phone_conflict(target)
    target
  end

  private

  def source_id
    @source_id ||= conversation.contact_inbox&.source_id.to_s.strip
  end

  def normalized_jid(identifier)
    user, server = identifier.to_s.downcase.split('@', 2)
    return if server.blank?

    user = user.split(':').first
    return "#{user}@g.us" if server == 'g.us' && user.match?(/\A[1-9][\d-]+\z/)
    return unless %w[s.whatsapp.net lid].include?(server) && user.match?(/\A[1-9]\d+\z/)

    "#{user}@#{server}"
  end

  def normalized_phone_jid(identifier)
    return if identifier.blank? || identifier.include?('@')

    digits = identifier.delete('^0-9')
    "#{digits}@s.whatsapp.net" if digits.match?(/\A[1-9]\d{9,14}\z/)
  end

  def log_contact_phone_conflict(target)
    return unless target.end_with?('@s.whatsapp.net')

    contact_phone = normalized_phone_jid(conversation.contact&.phone_number.to_s)
    return if contact_phone.blank? || contact_phone == target

    Rails.logger.error(
      "Whatsmeow: ignored conflicting contact phone for conversation #{conversation.id}; " \
      'using authoritative contact_inbox source_id'
    )
  end

  def invalid_target_error
    CustomExceptions::Whatsmeow::InvalidConversationTarget.new(
      "Invalid WhatsApp contact_inbox source_id for conversation #{conversation.id}"
    )
  end
end
