class Whatsmeow::ContactIdentityReconciliationService
  pattr_initialize [:account!, { dry_run: true }]

  def perform
    @stats = Hash.new(0)
    account.inboxes.includes(:channel).where(channel_type: 'Channel::Whatsmeow').find_each do |inbox|
      reconcile_inbox(inbox)
    end
    @stats
  end

  private

  def reconcile_inbox(inbox)
    lid_source_ids = inbox.contact_inboxes.where("source_id LIKE '%@lid'").distinct.pluck(:source_id)
    return if lid_source_ids.blank?

    identities = resolved_identities(inbox, lid_source_ids)
    lid_source_ids.each do |lid_source_id|
      reconcile_identity(inbox, lid_source_id, identity_for(identities, lid_source_id))
    end
  rescue Whatsmeow::SessionClient::Error
    @stats[:inboxes_skipped] += 1
    @stats[:unresolved] += lid_source_ids.size
  end

  def resolved_identities(inbox, lid_source_ids)
    response = Whatsmeow::SessionClient.new(inbox: inbox).resolve_identities(lid_source_ids)
    Array(response['identities']).each_with_object({}) do |identity, result|
      result[identity['input_jid']] = identity
      result[identity['lid_jid']] = identity if identity['lid_jid'].present?
    end
  end

  def identity_for(identities, lid_source_id)
    identities[lid_source_id] || identities[normalized_lid_source_id(lid_source_id)]
  end

  def reconcile_identity(inbox, lid_source_id, identity)
    unless identity&.fetch('resolved', false)
      @stats[:unresolved] += 1
      return
    end

    phone_number = identity['phone_number']
    phone_jid = identity['phone_jid']
    source_ids = [phone_jid, lid_source_id, identity['lid_jid']].compact_blank.uniq
    contact_ids = identity_contact_ids(inbox, source_ids, phone_number)
    track_resolved_identity(inbox, source_ids, contact_ids)
    return if dry_run

    apply_identity(inbox, identity, source_ids, phone_number)
  end

  def track_resolved_identity(inbox, source_ids, contact_ids)
    @stats[:resolved] += 1
    @stats[:contacts_merged] += contact_ids.size - 1 if contact_ids.size > 1
    return unless identity_open_conversation_count(inbox, source_ids, contact_ids) > 1

    @stats[:conversation_groups_merged] += 1
  end

  def apply_identity(inbox, identity, source_ids, phone_number)
    Whatsmeow::ContactIdentityResolver.new(
      inbox: inbox,
      source_ids: source_ids,
      phone_number: phone_number,
      contact_attributes: {
        name: phone_number,
        phone_number: phone_number,
        additional_attributes: {
          whatsmeow_participant_lid_jid: identity['lid_jid'],
          whatsmeow_participant_phone: phone_number
        }.compact_blank
      }
    ).perform
  end

  def identity_contact_ids(inbox, source_ids, phone_number)
    contact_ids = inbox.contact_inboxes.where(source_id: source_ids).distinct.pluck(:contact_id)
    phone_contact_id = account.contacts.find_by(phone_number: phone_number)&.id
    (contact_ids + [phone_contact_id]).compact.uniq
  end

  def identity_open_conversation_count(inbox, source_ids, contact_ids)
    contact_inbox_ids = inbox.contact_inboxes.where(source_id: source_ids).select(:id)
    inbox.conversations.where(contact_id: contact_ids, contact_inbox_id: contact_inbox_ids)
         .where.not(status: :resolved).count
  end

  def normalized_lid_source_id(source_id)
    user, server = source_id.to_s.split('@', 2)
    "#{user.split(':').first}@#{server}"
  end
end
