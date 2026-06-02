class Whatsmeow::ProfilePictureSyncJob < ApplicationJob
  queue_as :low

  REFRESH_INTERVAL = 24.hours

  def perform(contact_id, inbox_id, source_id = nil, force: false)
    @contact = Contact.find_by(id: contact_id)
    @inbox = Inbox.find_by(id: inbox_id)
    @source_id = source_id
    @force = force

    return unless syncable?
    return if recently_checked?

    profile_picture_url = fetch_profile_picture_url
    update_check_metadata(profile_picture_url)
    return if profile_picture_url.blank?

    ::Avatar::AvatarFromUrlJob.perform_later(@contact, profile_picture_url, force: force_avatar_download?(profile_picture_url))
  end

  private

  def syncable?
    @contact.present? && @inbox&.channel_type == 'Channel::Whatsmeow'
  end

  def recently_checked?
    return false if @force
    return false if !@contact.avatar.attached? && stored_profile_picture_url.present?

    checked_at = additional_attributes['whatsmeow_profile_picture_checked_at']
    checked_at.present? && Time.zone.parse(checked_at) > REFRESH_INTERVAL.ago
  rescue ArgumentError
    false
  end

  def fetch_profile_picture_url
    client = Whatsmeow::SessionClient.new(inbox: @inbox)
    profile_picture_candidates.each do |jid|
      payload = client.profile_picture(jid, force: @force)
      url = payload['profile_picture_url'].presence
      return url if url.present?
    rescue Whatsmeow::SessionClient::Error => e
      Rails.logger.info("Whatsmeow: profile picture lookup failed for contact #{@contact.id} on inbox #{@inbox.id}: #{e.message}")
    end

    nil
  end

  def profile_picture_candidates
    candidates = []
    candidates << phone_jid(@contact.phone_number)
    candidates << group_jid
    candidates << @source_id
    candidates.concat(contact_inbox_source_ids)
    candidates.concat(participant_jids)
    candidates << jid_like_name
    candidates.compact_blank.uniq
  end

  def contact_inbox_source_ids
    @contact.contact_inboxes.where(inbox_id: @inbox.id).pluck(:source_id)
  end

  def participant_jids
    [
      additional_attributes['whatsmeow_participant_jid'],
      additional_attributes['whatsmeow_participant_lid_jid'],
      phone_jid(additional_attributes['whatsmeow_participant_phone'])
    ]
  end

  def group_jid
    additional_attributes['whatsmeow_group_jid'] if group_profile?
  end

  def group_profile?
    additional_attributes.fetch('whatsmeow_group', false)
  end

  def phone_jid(phone_number)
    return if phone_number.blank?

    digits = phone_number.to_s.delete('^0-9')
    return if digits.blank?

    "#{digits}@s.whatsapp.net"
  end

  def jid_like_name
    @contact.name if @contact.name.to_s.include?('@')
  end

  def force_avatar_download?(profile_picture_url)
    @force || !@contact.avatar.attached? || profile_picture_url != stored_profile_picture_url
  end

  def update_check_metadata(profile_picture_url)
    @contact.update_columns( # rubocop:disable Rails/SkipsModelValidations
      additional_attributes: additional_attributes.merge(
        'whatsmeow_profile_picture_checked_at' => Time.current.iso8601,
        'whatsmeow_profile_picture_url' => profile_picture_url
      ).compact
    )
  end

  def stored_profile_picture_url
    additional_attributes['whatsmeow_profile_picture_url']
  end

  def additional_attributes
    @additional_attributes ||= (@contact.additional_attributes || {})
  end
end
