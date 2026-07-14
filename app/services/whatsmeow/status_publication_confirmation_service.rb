class Whatsmeow::StatusPublicationConfirmationService
  pattr_initialize [:inbox!, :params!]

  def perform
    return false if source_ids.blank? || published_at.blank?

    confirmed = false
    WhatsmeowStatus.transaction do
      status = matching_status
      next if status.blank?

      delivery_scope(status).each { |delivery| confirm_delivery(delivery) }
      confirmed = true
    end

    confirmed
  end

  private

  def source_ids
    @source_ids ||= [params[:message_id], params[:requested_message_id]].compact_blank.uniq
  end

  def published_at
    timestamp = params[:timestamp].to_i
    return if timestamp <= 0

    @published_at ||= Time.zone.at(timestamp)
  end

  def matching_status
    @inbox.whatsmeow_statuses.where(source_id: source_ids).order(:id).lock.first
  end

  def delivery_scope(status)
    return [status] if status.publication_id.blank? || status.session_key.blank?

    status.account.whatsmeow_statuses
          .where(publication_id: status.publication_id, session_key: status.session_key)
          .lock
          .to_a
  end

  def confirm_delivery(status)
    status.update!(
      sender_jid: sender_jid(status),
      sender_name: status.inbox.name,
      sender_phone: status.inbox.channel.phone_number,
      from_me: true,
      posted_at: published_at,
      expires_at: published_at + 24.hours,
      publication_state: :published,
      last_error: nil,
      next_attempt_at: nil
    )
  end

  def sender_jid(status)
    params[:sender].presence || status.sender_jid.presence || own_jid(status.inbox)
  end

  def own_jid(inbox)
    phone = inbox.channel.phone_number.to_s.delete('^0-9')
    "#{phone}@s.whatsapp.net"
  end
end
