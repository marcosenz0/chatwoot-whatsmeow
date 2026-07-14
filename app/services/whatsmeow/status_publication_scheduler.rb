require 'securerandom'
require 'digest'

class Whatsmeow::StatusPublicationScheduler
  UUID_PATTERN = /\A[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i

  pattr_initialize [:inboxes!, :user!, :params!]

  def perform
    validate_payload!
    return enqueue_existing(existing_statuses) if existing_statuses.any?

    blob = create_media_blob
    statuses = create_statuses(blob)
    enqueue_statuses(statuses)
    statuses
  rescue StandardError
    blob&.purge_later if blob&.attachments&.none?
    raise
  end

  private

  def account
    inboxes.first.account
  end

  def publication_id
    @publication_id ||= params[:publication_id].presence || SecureRandom.uuid
  end

  def existing_statuses
    @existing_statuses ||= account.whatsmeow_statuses
                                  .where(publication_id: publication_id)
                                  .includes(inbox: :channel, media_attachment: :blob)
                                  .order(:publication_position, :id)
                                  .to_a
  end

  def enqueue_existing(statuses)
    validate_existing!(statuses)
    enqueue_statuses(statuses)
    statuses
  end

  def validate_existing!(statuses)
    return if statuses.first.metadata['publication_fingerprint'] == publication_fingerprint

    raise ArgumentError, 'Publication ID has already been used with different Status content'
  end

  def validate_payload!
    raise ArgumentError, 'Select at least one connected WhatsApp inbox' if inboxes.blank?
    raise ArgumentError, 'Invalid publication ID' unless publication_id.match?(UUID_PATTERN)
    raise ArgumentError, 'Status content or media is required' if content.blank? && media.blank?
    raise ArgumentError, 'Status text is too long' if content.length > 700

    validate_media! if media.present?
  end

  def validate_media!
    raise ArgumentError, 'Only image, video and audio statuses are supported' unless %w[image video audio].include?(status_type)
    raise ArgumentError, 'Status media is too large' if media.size > maximum_media_size
  end

  def create_statuses(blob)
    statuses, used_existing = WhatsmeowStatus.transaction { create_statuses_under_lock(blob) }
    blob.purge_later if used_existing && blob&.attachments&.none?
    statuses
  rescue ActiveRecord::RecordNotUnique
    recover_existing_statuses(blob)
  end

  def create_statuses_under_lock(blob)
    acquire_publication_lock
    @existing_statuses = nil
    return [create_new_statuses(blob), false] if existing_statuses.empty?

    validate_existing!(existing_statuses)
    [existing_statuses, true]
  end

  def recover_existing_statuses(blob)
    blob.purge_later if blob&.attachments&.none?
    @existing_statuses = nil
    statuses = existing_statuses.presence || raise
    validate_existing!(statuses)
    statuses
  end

  def acquire_publication_lock
    lock_key = Digest::SHA256.hexdigest("#{account.id}:#{publication_id}").first(15).to_i(16)
    WhatsmeowStatus.connection.select_value("SELECT pg_advisory_xact_lock(#{lock_key})")
  end

  def create_new_statuses(blob)
    now = Time.current
    session_groups.each_with_index.flat_map do |(key, group), position|
      create_session_statuses(group, key, position, now, blob)
    end
  end

  def session_groups
    inboxes.group_by { |inbox| session_key(inbox) }
  end

  def create_session_statuses(inbox_group, key, position, now, blob)
    source_id = "3EB0#{SecureRandom.hex(9).upcase}"
    inbox_group.map do |inbox|
      status = build_status(inbox, key, position, source_id, now)
      status.media.attach(blob) if blob.present?
      status.save!
      status
    end
  end

  def build_status(inbox, key, position, source_id, now)
    inbox.whatsmeow_statuses.new(
      account: account,
      created_by: user,
      source_id: source_id,
      sender_jid: own_jid(inbox),
      sender_name: inbox.name,
      sender_phone: inbox.channel.phone_number,
      status_type: status_type,
      content: content.presence,
      from_me: true,
      posted_at: now,
      expires_at: now + 24.hours,
      metadata: presentation_metadata,
      publication_id: publication_id,
      session_key: key,
      publication_position: position,
      publication_state: :queued
    )
  end

  def presentation_metadata
    @presentation_metadata ||= Whatsmeow::StatusPublisher.presentation_metadata(params).merge(
      'publication_id' => publication_id,
      'publication_fingerprint' => publication_fingerprint
    )
  end

  def publication_fingerprint
    @publication_fingerprint ||= Digest::SHA256.hexdigest(
      [fingerprint_inbox_ids, content, params[:background], params[:font], media_fingerprint].to_json
    )
  end

  def fingerprint_inbox_ids
    inboxes.map(&:id).sort unless params[:legacy_single_inbox]
  end

  def media_fingerprint
    return if media.blank?

    digest = Digest::SHA256.file(media.tempfile.path).hexdigest
    [media.original_filename, media.content_type, media.size, digest]
  end

  def create_media_blob
    return if media.blank?

    media.rewind
    ActiveStorage::Blob.create_and_upload!(
      io: media,
      filename: media.original_filename,
      content_type: media.content_type
    )
  ensure
    media&.rewind
  end

  def enqueue_statuses(statuses)
    Whatsmeow::StatusPublicationEnqueuer.new(statuses: statuses).perform
  end

  def content
    @content ||= params[:content].to_s.strip
  end

  def media
    params[:media]
  end

  def status_type
    return 'text' if media.blank?
    return 'image' if media.content_type.to_s.start_with?('image/')
    return 'video' if media.content_type.to_s.start_with?('video/')
    return 'audio' if media.content_type.to_s.start_with?('audio/')

    'file'
  end

  def session_key(inbox)
    phone = inbox.channel.phone_number.to_s.delete('^0-9')
    phone.present? ? "phone:#{phone}" : "inbox:#{inbox.id}"
  end

  def own_jid(inbox)
    phone = inbox.channel.phone_number.to_s.delete('^0-9')
    "#{phone}@s.whatsapp.net"
  end

  def maximum_media_size
    limit_mb = GlobalConfigService.load('MAXIMUM_FILE_UPLOAD_SIZE', 40).to_i
    limit_mb = 40 if limit_mb <= 0
    limit_mb.megabytes
  end
end
