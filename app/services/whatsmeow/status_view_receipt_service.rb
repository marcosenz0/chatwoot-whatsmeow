class Whatsmeow::StatusViewReceiptService
  pattr_initialize [:inbox!, :params!]

  def perform
    return if viewer_jid.blank?

    statuses.find_each { |status| upsert_viewer(status) }
  end

  private

  def statuses
    @inbox.whatsmeow_statuses.where(from_me: true, source_id: status_source_ids)
  end

  def status_source_ids
    @status_source_ids ||= Array(params[:message_ids]).compact_blank.presence ||
                           [params[:message_id], params[:source_status_id], params[:status_id], params[:status_message_id]].compact_blank
  end

  def upsert_viewer(status)
    viewer = status.status_viewers.find_or_initialize_by(viewer_jid: viewer_jid)
    update_viewer(viewer)
  rescue ActiveRecord::RecordNotUnique
    update_viewer(status.status_viewers.find_by!(viewer_jid: viewer_jid))
  end

  def update_viewer(viewer)
    viewer.update!(
      contact: contact,
      viewer_name: viewer_name,
      viewer_phone: viewer_phone,
      viewed_at: viewed_at
    )
  end

  def viewer_jid
    @viewer_jid ||= [params[:viewer_jid], params[:viewer], params[:sender], params[:sender_alt], params[:participant]]
                    .compact_blank.first.to_s.strip.downcase.presence
  end

  def viewer_phone
    @viewer_phone ||= params[:viewer_phone].presence || params[:sender_phone].presence || phone_from_jid(viewer_jid)
  end

  def viewer_name
    @viewer_name ||= [
      params[:viewer_name],
      params[:sender_name],
      params[:push_name],
      contact&.name,
      viewer_phone,
      viewer_jid
    ].compact_blank.first
  end

  def viewed_at
    timestamp = params[:timestamp].to_i
    timestamp.positive? ? Time.zone.at(timestamp) : Time.current
  end

  def contact
    @contact ||= contact_from_inbox || contact_from_phone
  end

  def contact_from_inbox
    source_ids = [viewer_jid, phone_jid].compact_blank
    @inbox.contact_inboxes.includes(:contact).find_by(source_id: source_ids)&.contact
  end

  def contact_from_phone
    return if viewer_phone.blank?

    @inbox.account.contacts.find_by(phone_number: viewer_phone)
  end

  def phone_jid
    return if viewer_phone.blank?

    "#{viewer_phone.delete('^0-9')}@s.whatsapp.net"
  end

  def phone_from_jid(value)
    return if value.blank? || value.to_s.exclude?('@s.whatsapp.net')

    digits = value.to_s.split('@').first.split(':').first.delete('^0-9')
    "+#{digits}" if digits.present?
  end
end
