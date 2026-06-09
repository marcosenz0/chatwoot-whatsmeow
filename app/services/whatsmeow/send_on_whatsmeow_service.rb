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
      attachments: attachments_payload,
      contacts: contacts_payload,
      quoted: quoted_payload
    }.compact_blank
  end

  def attachments_payload
    message.attachments.filter_map do |attachment|
      next unless attachment.file.attached?

      {
        file_name: attachment.file.filename.to_s,
        content_type: attachment.file.content_type,
        file_type: attachment.file_type,
        meta: attachment.meta || {},
        recorded_audio: recorded_audio? && attachment.audio?,
        data_base64: Base64.strict_encode64(attachment.file.download)
      }
    end
  end

  def body_content
    message.content.to_s.strip
  end

  def contacts_payload
    contacts = message_content_attributes[:whatsmeow_contacts].presence || message_content_attributes[:whatsmeow_contact].presence

    Array.wrap(contacts).filter_map do |contact|
      next unless contact.respond_to?(:with_indifferent_access)

      normalized_contact_payload(contact.with_indifferent_access)
    end
  end

  def normalized_contact_payload(contact)
    {
      display_name: contact[:display_name],
      full_name: contact[:full_name],
      first_name: contact[:first_name],
      last_name: contact[:last_name],
      phone_number: contact[:phone_number],
      whatsapp_id: contact[:whatsapp_id],
      jid: contact[:jid],
      organization: contact[:organization],
      title: contact[:title],
      email: contact[:email],
      website: contact[:website],
      note: contact[:note],
      category: contact[:category],
      avatar_url: contact[:avatar_url],
      profile_picture_url: contact[:profile_picture_url],
      business_profile: contact[:business_profile],
      vcard: contact[:vcard]
    }.compact_blank
  end

  def quoted_payload
    quoted_message = reply_to_message
    return if quoted_message.blank? || quoted_message.source_id.blank?

    {
      message_id: quoted_message.source_id,
      participant: quoted_participant(quoted_message),
      text: quoted_message.content.to_s.strip,
      file_type: quoted_file_type(quoted_message),
      from_me: quoted_message.outgoing?
    }.compact_blank
  end

  def reply_to_message
    return @reply_to_message if defined?(@reply_to_message)

    @reply_to_message = begin
      relation = message.conversation.messages
      local_id = message_content_attributes[:in_reply_to].presence
      external_id = message_content_attributes[:in_reply_to_external_id].presence

      local_message = relation.find_by(id: local_id) if local_id
      external_message = relation.find_by(source_id: external_id) if external_id

      local_message || external_message
    end
  end

  def message_content_attributes
    @message_content_attributes ||= (message.content_attributes || {}).with_indifferent_access
  end

  def quoted_participant(quoted_message)
    return unless group_jid?(source_id)
    return if quoted_message.outgoing?

    content_attributes = (quoted_message.content_attributes || {}).with_indifferent_access

    [
      content_attributes[:participant_jid],
      content_attributes[:participant_lid_jid],
      phone_jid(content_attributes[:participant_phone]),
      quoted_message.sender&.additional_attributes&.dig('whatsmeow_participant_jid'),
      quoted_message.sender&.additional_attributes&.dig('whatsmeow_participant_lid_jid'),
      phone_jid(quoted_message.sender&.phone_number)
    ].compact_blank.find { |identifier| deliverable_jid?(identifier) }
  end

  def quoted_file_type(quoted_message)
    quoted_message.attachments.first&.file_type
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
    return if identifier.blank?

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
