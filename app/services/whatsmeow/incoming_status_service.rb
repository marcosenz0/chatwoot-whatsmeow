require 'base64'
require 'stringio'

class Whatsmeow::IncomingStatusService
  pattr_initialize [:inbox!, :params!]

  def perform
    return unless importable?

    status = @inbox.whatsmeow_statuses.find_or_initialize_by(source_id: params[:message_id])
    status.assign_attributes(status_attributes(status))
    status.read_receipt_sent_at ||= Time.current if already_viewed?
    attach_media(status) if attachment.present? && !status.media.attached?
    status.save!
    confirm_publication(status) if boolean_param(:from_me)
    sync_contact_avatar
    status
  rescue ActiveRecord::RecordNotUnique
    @inbox.whatsmeow_statuses.find_by(source_id: params[:message_id])
  end

  private

  def importable?
    return false if params[:message_id].blank? || expired?
    return false if attachment.present? && media_data.blank?

    content.present? || media_data.present?
  end

  def posted_at
    @posted_at ||= Time.zone.at(params[:timestamp].to_i)
  end

  def expired?
    posted_at <= 24.hours.ago
  end

  def expires_at
    posted_at + 24.hours
  end

  def status_attributes(status)
    {
      account: @inbox.account,
      contact: contact,
      sender_jid: sender_jid,
      sender_name: sender_name,
      sender_phone: sender_phone,
      status_type: status_type,
      content: content,
      from_me: boolean_param(:from_me),
      posted_at: posted_at,
      expires_at: expires_at,
      metadata: metadata(status.metadata)
    }
  end

  def boolean_param(key)
    ActiveModel::Type::Boolean.new.cast(params[key])
  end

  def already_viewed?
    boolean_param(:status_already_viewed)
  end

  def sender_jid
    params[:sender].presence || params[:sender_alt].presence || params[:chat].presence
  end

  def sender_phone
    @sender_phone ||= params[:sender_phone].presence || phone_from_jid(params[:sender]) || phone_from_jid(params[:sender_alt])
  end

  def sender_name
    contact&.name.presence || params[:sender_name].presence || sender_phone.presence || sender_jid
  end

  def content
    params[:content].to_s.presence
  end

  def attachment
    @attachment ||= Array(params[:attachments]).filter_map do |item|
      item.with_indifferent_access if item.respond_to?(:with_indifferent_access)
    end.first
  end

  def status_type
    type = attachment&.dig(:file_type).to_s
    return type if WhatsmeowStatus.status_types.key?(type)

    'text'
  end

  def metadata(existing_metadata)
    status_metadata = params[:status_metadata].respond_to?(:to_h) ? params[:status_metadata].to_h : {}
    existing_metadata.to_h.stringify_keys.merge(status_metadata.stringify_keys).merge(
      'profile_picture_url' => params[:profile_picture_url],
      'status_already_viewed' => already_viewed?
    ).compact_blank
  end

  def contact
    @contact ||= contact_from_inbox || contact_from_phone
  end

  def contact_from_inbox
    source_ids = [params[:sender], params[:sender_alt], phone_jid].compact_blank
    @inbox.contact_inboxes.includes(:contact).find_by(source_id: source_ids)&.contact
  end

  def contact_from_phone
    return if sender_phone.blank?

    @inbox.account.contacts.find_by(phone_number: sender_phone)
  end

  def phone_jid
    return if sender_phone.blank?

    "#{sender_phone.delete('^0-9')}@s.whatsapp.net"
  end

  def phone_from_jid(value)
    return if value.blank? || value.to_s.exclude?('@s.whatsapp.net')

    digits = value.to_s.split('@').first.split(':').first.delete('^0-9')
    "+#{digits}" if digits.present?
  end

  def attach_media(status)
    status.media.attach(
      io: StringIO.new(media_data),
      filename: attachment[:file_name].presence || "whatsapp-status.#{default_extension}",
      content_type: normalized_content_type
    )
  end

  def media_data
    return @media_data if defined?(@media_data)

    encoded_data = attachment&.dig(:data_base64).to_s
    return @media_data = nil if encoded_data.blank? || encoded_data.bytesize > maximum_encoded_media_size

    @media_data = Base64.strict_decode64(encoded_data)
  rescue ArgumentError
    @media_data = nil
  end

  def maximum_encoded_media_size
    ((maximum_media_size * 4) / 3) + 4
  end

  def maximum_media_size
    limit_mb = GlobalConfigService.load('MAXIMUM_FILE_UPLOAD_SIZE', 40).to_i
    limit_mb = 40 if limit_mb <= 0
    limit_mb.megabytes
  end

  def normalized_content_type
    attachment[:content_type].to_s.split(';').first.strip.downcase.presence || 'application/octet-stream'
  end

  def default_extension
    { 'image' => 'jpg', 'video' => 'mp4', 'audio' => 'ogg' }.fetch(status_type, 'bin')
  end

  def sync_contact_avatar
    return if contact.blank? || params[:profile_picture_url].blank?

    Avatar::AvatarFromUrlJob.perform_later(contact, params[:profile_picture_url], force: false)
  end

  def confirm_publication(status)
    Whatsmeow::StatusPublicationConfirmationService.new(inbox: @inbox, params: params).perform
    status.reload
  end
end
