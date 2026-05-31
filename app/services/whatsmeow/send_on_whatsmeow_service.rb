class Whatsmeow::SendOnWhatsmeowService
  pattr_initialize [:message!]

  def perform
    return if message.incoming?
    return if message.private?
    return if message.source_id.present?

    inbox = message.conversation.inbox
    target_jid = target_identifier
    raise "No deliverable WhatsApp target found for conversation #{message.conversation_id}" if target_jid.blank?

    payload = {
      channel_id: inbox.id.to_s,
      to: target_jid,
      body: message.content
    }

    Rails.logger.info("Whatsmeow: Sending outgoing message to #{target_jid} on inbox #{inbox.id} via Go API...")

    result = Whatsmeow::SessionClient.request(:post, '/messages', body: payload)
    message.update!(source_id: result['id']) if result['id'].present?
    Rails.logger.info("Whatsmeow: Message dispatched successfully. External ID: #{result['id']}")
  rescue StandardError => e
    message.update!(status: :failed, content_attributes: (message.content_attributes || {}).merge(external_error: e.message))
    Rails.logger.error("Whatsmeow: Exception occurred while sending message: #{e.message}")
  end

  private

  def target_identifier
    source_id = message.conversation.contact_inbox&.source_id
    candidates = [
      message.conversation.contact&.name,
      message.conversation.contact&.phone_number,
      source_id
    ].compact_blank

    phone_identifier = candidates.find { |identifier| phone_identifier?(identifier, source_id) }
    return phone_jid(phone_identifier) if phone_identifier.present?

    candidates.find { |identifier| deliverable_jid?(identifier) }
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
    jid.include?('@') && !jid.include?('@newsletter')
  end

  def non_phone_jid?(identifier)
    jid = identifier.to_s.downcase
    jid.include?('@lid') || jid.include?('@newsletter')
  end

  def lid_digits(identifier)
    return unless identifier.to_s.downcase.include?('@lid')

    identifier.to_s.split('@').first.split(':').first.delete('^0-9')
  end
end
