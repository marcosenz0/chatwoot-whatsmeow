class Whatsmeow::SendOnWhatsmeowService
  pattr_initialize [:message!]

  def perform
    return unless deliverable_message?

    dispatch_message
  rescue StandardError => e
    mark_failed(e.message)
    Rails.logger.error("Whatsmeow: Exception occurred while sending message: #{e.message}")
  end

  private

  def deliverable_message?
    !message.incoming? && !message.private? && message.source_id.blank?
  end

  def dispatch_message
    Rails.logger.info("Whatsmeow: Sending outgoing message to #{target_identifier} on inbox #{inbox.id} via Go API...")

    result = Whatsmeow::SessionClient.request(:post, '/messages', body: payload)
    update_source_id(result)
  end

  def payload
    {
      channel_id: inbox.id.to_s,
      to: target_identifier,
      body: message.content
    }
  end

  def inbox
    @inbox ||= message.conversation.inbox
  end

  def target_identifier
    @target_identifier ||= resolve_target_identifier
  end

  def resolve_target_identifier
    phone_identifier = target_candidates.find { |identifier| phone_identifier?(identifier, source_id) }
    return phone_jid(phone_identifier) if phone_identifier.present?

    deliverable_jid || missing_target!
  end

  def target_candidates
    [
      message.conversation.contact&.name,
      message.conversation.contact&.phone_number,
      source_id
    ].compact_blank
  end

  def source_id
    @source_id ||= message.conversation.contact_inbox&.source_id
  end

  def deliverable_jid
    target_candidates.find { |identifier| deliverable_jid?(identifier) }
  end

  def phone_identifier?(identifier, source_id = nil)
    return false if non_phone_jid?(identifier)

    digits = identifier.to_s.split('@').first.split(':').first.delete('^0-9')
    digits.match?(/\A[1-9]\d{1,14}\z/) && digits != lid_digits(source_id)
  end

  def phone_jid(identifier)
    "#{identifier.to_s.split('@').first.split(':').first.delete('^0-9')}@s.whatsapp.net"
  end

  def deliverable_jid?(identifier)
    jid = identifier.to_s.downcase
    jid.include?('@') && jid.exclude?('@newsletter')
  end

  def non_phone_jid?(identifier)
    jid = identifier.to_s.downcase
    return false unless jid.include?('@')

    jid.exclude?('@s.whatsapp.net')
  end

  def lid_digits(identifier)
    return unless identifier.to_s.downcase.include?('@lid')

    identifier.to_s.split('@').first.split(':').first.delete('^0-9')
  end

  def update_source_id(result)
    message.update!(source_id: result['id']) if result['id'].present?
    Rails.logger.info("Whatsmeow: Message dispatched successfully. External ID: #{result['id']}")
  end

  def mark_failed(error_message)
    message.update!(status: :failed, content_attributes: (message.content_attributes || {}).merge(external_error: error_message))
  end

  def missing_target!
    raise "No deliverable WhatsApp target found for conversation #{message.conversation_id}"
  end
end
