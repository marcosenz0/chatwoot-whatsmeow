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
    viewers = matching_viewers(status).order(:id).to_a
    viewer = viewers.shift || status.status_viewers.new

    WhatsmeowStatusViewer.transaction do
      viewers.each(&:destroy!)
      update_viewer(viewer)
    end
  rescue ActiveRecord::RecordNotUnique
    update_viewer(status.status_viewers.find_by!(viewer_jid: canonical_viewer_jid))
  end

  def update_viewer(viewer)
    viewer.update!(
      viewer_jid: canonical_viewer_jid,
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
    return @viewer_phone if defined?(@viewer_phone)

    value = params[:viewer_phone].presence || params[:sender_phone].presence || phone_from_jid(viewer_jid)
    digits = value.to_s.delete('^0-9')
    @viewer_phone = "+#{digits}" if digits.present?
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

  def canonical_viewer_jid
    phone_jid || viewer_jid
  end

  def matching_viewers(status)
    scope = status.status_viewers.where(viewer_jid: [viewer_jid, phone_jid].compact)
    scope = scope.or(status.status_viewers.where(contact_id: contact.id)) if contact.present?
    scope = scope.or(status.status_viewers.where(viewer_phone: viewer_phone)) if viewer_phone.present?
    scope
  end

  def phone_from_jid(value)
    return if value.blank? || value.to_s.exclude?('@s.whatsapp.net')

    digits = value.to_s.split('@').first.split(':').first.delete('^0-9')
    "+#{digits}" if digits.present?
  end
end
