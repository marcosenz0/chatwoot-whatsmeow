require 'base64'

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
    message.outgoing? && !message.private? && message.source_id.blank?
  end

  def dispatch_message
    targets = target_identifiers

    targets.each_with_index do |identifier, index|
      @target_identifier = identifier
      begin
        Rails.logger.info("Whatsmeow: Sending outgoing message to #{target_identifier} on inbox #{inbox.id} via Go API...")

        result = Whatsmeow::SessionClient.request(:post, '/messages', body: payload)
        update_source_id(result)
        return
      rescue Whatsmeow::SessionClient::Error => e
        raise e unless retryable_target_error?(e) && index < targets.length - 1

        Rails.logger.warn(
          "Whatsmeow: Send to #{target_identifier} failed with #{e.message}; trying alternate participant JID..."
        )
      end
    end
  end

  def payload
    {
      channel_id: inbox.id.to_s,
      to: target_identifier,
      body: body_content,
      attachments: attachments_payload
    }
  end

  def attachments_payload
    message.attachments.filter_map do |attachment|
      next unless attachment.file.attached?

      {
        file_name: attachment.file.filename.to_s,
        content_type: attachment.file.content_type,
        file_type: attachment.file_type,
        recorded_audio: recorded_audio? && attachment.audio?,
        data_base64: Base64.strict_encode64(attachment.file.download)
      }
    end
  end

  def body_content
    message.content.to_s.strip
  end

  def inbox
    @inbox ||= message.conversation.inbox
  end

  def target_identifier
    @target_identifier ||= target_identifiers.first
  end

  def target_identifiers
    @target_identifiers ||= resolve_target_identifiers
  end

  def resolve_target_identifiers
    return [source_id] if group_jid?(source_id)

    targets = target_candidates.filter_map do |identifier|
      phone_jid(identifier) if phone_identifier?(identifier, source_id)
    end
    targets += target_candidates.select { |identifier| deliverable_jid?(identifier) }
    targets = targets.compact_blank.uniq
    return targets if targets.present?

    missing_target!
  end

  def target_candidates
    contact = message.conversation.contact
    additional_attributes = contact&.additional_attributes || {}

    [
      additional_attributes['whatsmeow_participant_jid'],
      contact&.phone_number,
      additional_attributes['whatsmeow_participant_phone'],
      source_id,
      additional_attributes['whatsmeow_participant_lid_jid'],
      contact&.name
    ].compact_blank
  end

  def source_id
    @source_id ||= message.conversation.contact_inbox&.source_id
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

  def group_jid?(identifier)
    identifier.to_s.downcase.include?('@g.us')
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

  def recorded_audio?
    ActiveModel::Type::Boolean.new.cast(message.content_attributes&.dig('whatsmeow_recorded_audio'))
  end

  def update_source_id(result)
    message.update!(source_id: result['id']) if result['id'].present?
    Rails.logger.info("Whatsmeow: Message dispatched successfully. External ID: #{result['id']}")
  end

  def retryable_target_error?(error)
    error.message.include?('server returned error 403')
  end

  def mark_failed(error_message)
    message.update!(status: :failed, content_attributes: (message.content_attributes || {}).merge(external_error: error_message))
  end

  def missing_target!
    raise "No deliverable WhatsApp target found for conversation #{message.conversation_id}"
  end
end
