require 'base64'

class Whatsmeow::StatusPublisher
  BACKGROUNDS = {
    'teal' => 0xFF0B8467,
    'blue' => 0xFF176BCE,
    'violet' => 0xFF6750A4,
    'amber' => 0xFFB85C00,
    'ruby' => 0xFFA6294F,
    'slate' => 0xFF30363D
  }.freeze
  FONTS = { 'system' => 0, 'bold' => 6, 'serif' => 8, 'modern' => 9, 'mono' => 10 }.freeze

  pattr_initialize [:status!]

  class << self
    def presentation_metadata(params)
      background = BACKGROUNDS.key?(params[:background].to_s) ? params[:background].to_s : 'teal'
      font = FONTS.key?(params[:font].to_s) ? params[:font].to_s : 'bold'

      {
        'background' => background,
        'background_argb' => BACKGROUNDS.fetch(background),
        'text_argb' => 0xFFFFFFFF,
        'font' => font,
        'font_value' => FONTS.fetch(font)
      }
    end
  end

  def perform
    validate_status!
    response = Whatsmeow::SessionClient.new(inbox: status.inbox).publish_status(outbound_payload)
    persist_response!(response)
  end

  private

  delegate :account, to: :status

  def validate_status!
    raise ArgumentError, 'Status content or media is required' if status.content.blank? && !status.media.attached?
    raise ArgumentError, 'Status text is too long' if status.content.to_s.length > 700

    validate_media! if status.media.attached?
  end

  def validate_media!
    raise ArgumentError, 'Only image, video and audio statuses are supported' unless status.image? || status.video? || status.audio?
  end

  def outbound_payload
    payload = {
      message_id: status.source_id,
      content: status.content.to_s,
      background_argb: status.metadata['background_argb'],
      text_argb: status.metadata['text_argb'],
      font: status.metadata['font_value'],
      contacts: audience_contacts,
      managed_contacts: managed_contacts
    }
    payload[:attachment] = attachment_payload if status.media.attached?
    payload
  end

  def attachment_payload
    {
      file_name: status.media.filename.to_s,
      content_type: status.media.content_type,
      file_type: status.status_type,
      recorded_audio: status.audio?,
      data_base64: Base64.strict_encode64(status.media.download)
    }
  end

  def persist_response!(response)
    response_id = response['id'].presence || raise(Whatsmeow::SessionClient::Error, 'WhatsApp did not return a Status ID')
    raise Whatsmeow::SessionClient::Error, 'WhatsApp returned an unexpected Status ID' unless response_id == status.source_id

    timestamp = response['timestamp'].to_i
    raise Whatsmeow::SessionClient::Error, 'WhatsApp did not return a valid Status timestamp' unless timestamp.positive?

    posted_at = Time.zone.at(timestamp)
    sender_jid = response['jid'].presence || own_jid(status.inbox)
    WhatsmeowStatus.transaction do
      delivery_statuses.each { |delivery| mark_published(delivery, sender_jid, posted_at) }
    end

    status.reload
  end

  def mark_published(delivery, sender_jid, posted_at)
    delivery.update!(
      sender_jid: sender_jid,
      sender_name: delivery.inbox.name,
      sender_phone: delivery.inbox.channel.phone_number,
      posted_at: posted_at,
      expires_at: posted_at + 24.hours,
      publication_state: :published,
      last_error: nil,
      next_attempt_at: nil
    )
  end

  def delivery_statuses
    @delivery_statuses ||= if status.publication_id.present? && status.session_key.present?
                             account.whatsmeow_statuses
                                    .where(publication_id: status.publication_id, session_key: status.session_key)
                                    .includes(inbox: :channel)
                                    .to_a
                           else
                             [status]
                           end
  end

  def target_inboxes
    @target_inboxes ||= delivery_statuses.map(&:inbox).uniq(&:id)
  end

  def audience_contacts
    contacts = target_inboxes.flat_map do |inbox|
      inbox.contact_inboxes.includes(:contact).filter_map do |contact_inbox|
        jid = audience_jid(contact_inbox)
        next if jid.blank?

        { jid: jid, name: contact_inbox.contact.name.presence || contact_inbox.source_id }
      end
    end
    contacts.uniq { |contact| contact[:jid] }
  end

  def audience_jid(contact_inbox)
    source_id = contact_inbox.source_id.to_s
    return source_id if source_id.match?(/\A[1-9]\d{5,14}@s\.whatsapp\.net\z/)

    phone = contact_inbox.contact.phone_number.to_s.delete('^0-9')
    return if phone.blank? || !phone.match?(/\A[1-9]\d{5,14}\z/)

    "#{phone}@s.whatsapp.net"
  end

  def managed_contacts
    account.contacts.where.not(phone_number: [nil, '']).pluck(:phone_number).filter_map do |phone_number|
      phone = phone_number.to_s.delete('^0-9')
      next unless phone.match?(/\A[1-9]\d{5,14}\z/)

      { jid: "#{phone}@s.whatsapp.net" }
    end
  end

  def own_jid(inbox)
    phone = inbox.channel.phone_number.to_s.delete('^0-9')
    "#{phone}@s.whatsapp.net"
  end
end
