require 'base64'
require 'stringio'

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

  pattr_initialize [:inbox!, :user!, :params!]

  def perform
    validate_payload!
    response = Whatsmeow::SessionClient.new(inbox: @inbox).publish_status(outbound_payload)
    persist_status(response)
  end

  private

  def content
    @content ||= params[:content].to_s.strip
  end

  def media
    params[:media]
  end

  def validate_payload!
    raise ArgumentError, 'Status content or media is required' if content.blank? && media.blank?
    raise ArgumentError, 'Status text is too long' if content.length > 700
    return if media.blank?

    raise ArgumentError, 'Only image and video statuses are supported' unless %w[image video].include?(status_type)
    raise ArgumentError, 'Status media is too large' if media.size > maximum_media_size
  end

  def status_type
    return 'text' if media.blank?
    return 'image' if media.content_type.to_s.start_with?('image/')
    return 'video' if media.content_type.to_s.start_with?('video/')

    'file'
  end

  def outbound_payload
    payload = {
      content: content,
      background_argb: background_argb,
      text_argb: 0xFFFFFFFF,
      font: font_value,
      contacts: audience_contacts
    }
    payload[:attachment] = attachment_payload if media.present?
    payload
  end

  def attachment_payload
    media.rewind
    data = media.read
    media.rewind
    {
      file_name: media.original_filename,
      content_type: media.content_type,
      file_type: status_type,
      data_base64: Base64.strict_encode64(data)
    }
  end

  def persist_status(response)
    source_id = response['id'].presence || raise(Whatsmeow::SessionClient::Error, 'WhatsApp did not return a Status ID')
    timestamp = response['timestamp'].to_i
    raise Whatsmeow::SessionClient::Error, 'WhatsApp did not return a valid Status timestamp' unless timestamp.positive?

    posted_at = Time.zone.at(timestamp)
    sender_jid = response['jid'].presence || own_jid
    status = @inbox.whatsmeow_statuses.find_or_initialize_by(source_id: source_id)
    save_status(status, posted_at, sender_jid)
  rescue ActiveRecord::RecordNotUnique
    status = @inbox.whatsmeow_statuses.find_by!(source_id: source_id)
    save_status(status, posted_at, sender_jid)
  end

  def save_status(status, posted_at, sender_jid)
    status.assign_attributes(
      account: @inbox.account,
      created_by: @user,
      sender_jid: sender_jid,
      sender_name: @inbox.name,
      sender_phone: @inbox.channel.phone_number,
      status_type: status_type,
      content: content.presence,
      from_me: true,
      posted_at: posted_at,
      expires_at: posted_at + 24.hours,
      metadata: status_metadata
    )
    attach_media(status) if media.present? && !status.media.attached?
    status.save!
    status
  end

  def attach_media(status)
    media.rewind
    status.media.attach(io: StringIO.new(media.read), filename: media.original_filename, content_type: media.content_type)
    media.rewind
  end

  def status_metadata
    {
      'background' => background,
      'background_argb' => background_argb,
      'text_argb' => 0xFFFFFFFF,
      'font' => font,
      'font_value' => font_value
    }
  end

  def background
    BACKGROUNDS.key?(params[:background].to_s) ? params[:background].to_s : 'teal'
  end

  def background_argb
    BACKGROUNDS.fetch(background)
  end

  def font
    FONTS.key?(params[:font].to_s) ? params[:font].to_s : 'bold'
  end

  def font_value
    FONTS.fetch(font)
  end

  def own_jid
    phone = @inbox.channel.phone_number.to_s.delete('^0-9')
    "#{phone}@s.whatsapp.net"
  end

  def audience_contacts
    contacts = []
    @inbox.contact_inboxes.includes(:contact).find_each do |contact_inbox|
      jid = audience_jid(contact_inbox)
      next if jid.blank?

      contacts << { jid: jid, name: contact_inbox.contact.name.presence || contact_inbox.source_id }
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

  def maximum_media_size
    limit_mb = GlobalConfigService.load('MAXIMUM_FILE_UPLOAD_SIZE', 40).to_i
    limit_mb = 40 if limit_mb <= 0
    limit_mb.megabytes
  end
end
