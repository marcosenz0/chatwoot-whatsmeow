require 'fileutils'

# rubocop:disable Metrics/ClassLength
class Whatsmeow::ContactIdentityIncidentRepairService
  DIRECT_CONTACT_ATTRIBUTE_KEYS = %w[
    whatsmeow_group_participant
    whatsmeow_participant_jid
    whatsmeow_participant_lid_jid
    whatsmeow_participant_phone
  ].freeze

  pattr_initialize [:account!, { inbox_id: nil, contact_ids: [], apply: false, snapshot_dir: nil }]

  def perform
    build_plan
    validate_plan!
    load_contact_names
    report = repair_report
    return report unless apply
    return report.merge(snapshot_path: nil) if @affected_anchors.blank?

    snapshot_path = write_snapshot
    ActiveRecord::Base.transaction { apply_plan }
    reconcile_post_commit
    enqueue_profile_syncs

    report.merge(
      snapshot_path: snapshot_path.to_s,
      created_contact_ids: @created_contact_ids,
      post_commit_reconciled_messages: @post_commit_reconciled_messages,
      remaining_sender_mismatches: sender_mismatch_count,
      applied: true
    )
  end

  private

  def build_plan
    @detection_inboxes = detection_inboxes.includes(:channel).to_a
    @anchors = @detection_inboxes.flat_map { |inbox| inbox_anchors(inbox) }
    @detected_contact_ids = @anchors.pluck(:original_contact_id).uniq
    @affected_contact_ids = requested_contact_ids.presence || affected_contact_ids
    @inboxes = account_whatsmeow_inboxes.includes(:channel).to_a
    @anchors = @inboxes.flat_map { |inbox| inbox_anchors(inbox) }
    @affected_anchors = @anchors.select { |anchor| @affected_contact_ids.include?(anchor[:original_contact_id]) }
    @residual_contact_inboxes = residual_contact_inboxes
    @canonical_contacts = {}
    @created_contact_ids = []
    @profile_syncs = []
  end

  def detection_inboxes
    scope = account_whatsmeow_inboxes
    scope = scope.where(id: inbox_id) if inbox_id.present?
    scope
  end

  def account_whatsmeow_inboxes
    account.inboxes.where(channel_type: 'Channel::Whatsmeow')
  end

  def inbox_anchors(inbox)
    inbox.contact_inboxes.includes(:contact, :conversations).filter_map do |contact_inbox|
      conversation_ids = contact_inbox.conversations.pluck(:id)
      next if conversation_ids.blank?

      phone_number = phone_number_from_source(contact_inbox.source_id)
      next if phone_number.blank? || phone_number == normalized_phone(inbox.channel.phone_number)

      {
        inbox: inbox,
        contact_inbox: contact_inbox,
        conversation_ids: conversation_ids,
        phone_number: phone_number,
        original_contact_id: contact_inbox.contact_id
      }
    end
  end

  def affected_contact_ids
    @anchors.group_by { |anchor| anchor[:original_contact_id] }.filter_map do |contact_id, anchors|
      contact = account.contacts.find(contact_id)
      anchor_phones = anchors.pluck(:phone_number).uniq
      conversation_contact_mismatch = anchors.any? do |anchor|
        Conversation.where(id: anchor[:conversation_ids]).where.not(contact_id: contact_id).exists?
      end

      contact_id if anchor_phones.many? || normalized_phone(contact.phone_number) != anchor_phones.first || conversation_contact_mismatch
    end
  end

  def residual_contact_inboxes
    return [] if @affected_contact_ids.blank?

    anchor_ids = @affected_anchors.pluck(:contact_inbox).map(&:id)
    ContactInbox.where(inbox_id: @inboxes.map(&:id), contact_id: @affected_contact_ids)
                .where.not(id: anchor_ids)
                .includes(:inbox, :conversations)
                .to_a
  end

  def validate_plan!
    validate_apply_scope!
    validate_requested_contacts!
    validate_residual_contact_inboxes!
  end

  def validate_apply_scope!
    return unless apply && (inbox_id.blank? || requested_contact_ids.blank?)

    raise ArgumentError, 'INBOX_ID and ROOT_CONTACT_ID are required when applying the incident repair'
  end

  def validate_requested_contacts!
    missing_contact_ids = requested_contact_ids - account.contacts.where(id: requested_contact_ids).pluck(:id)
    raise ArgumentError, "Contacts do not belong to account #{account.id}: #{missing_contact_ids.join(', ')}" if missing_contact_ids.present?

    undetected_contact_ids = requested_contact_ids - @detected_contact_ids
    return if undetected_contact_ids.blank?

    raise ArgumentError, "Contacts are not anchored in detection inbox #{inbox_id}: #{undetected_contact_ids.join(', ')}"
  end

  def validate_residual_contact_inboxes!
    invalid_residual = @residual_contact_inboxes.find do |contact_inbox|
      contact_inbox.conversations.exists? && !group_source?(contact_inbox.source_id)
    end
    return unless invalid_residual

    raise CustomExceptions::Whatsmeow::InvalidConversationTarget,
          "Repair stopped: contact_inbox #{invalid_residual.id} has conversations but no canonical phone source"
  end

  def load_contact_names
    @contact_names = {}
    @resolved_alias_phones = {}
    contact_lookup_inboxes.each do |inbox|
      anchors = @affected_anchors.select { |anchor| anchor[:inbox].id == inbox.id }
      load_inbox_contact_names(inbox, anchors)
    end
  end

  def contact_lookup_inboxes
    anchor_inboxes = @affected_anchors.pluck(:inbox)
    residual_inboxes = @residual_contact_inboxes.map(&:inbox)
    (anchor_inboxes + residual_inboxes).uniq(&:id)
  end

  def load_inbox_contact_names(inbox, anchors)
    response = Whatsmeow::SessionClient.new(inbox: inbox).lookup_contacts(contact_lookup_jids(inbox, anchors))
    Array(response['contacts']).each { |contact| index_contact_lookup(inbox, contact) }
  rescue Whatsmeow::SessionClient::Error => e
    Rails.logger.warn("Whatsmeow identity repair could not load contact names for inbox #{inbox.id}: #{e.message}")
  end

  def contact_lookup_jids(inbox, anchors)
    residual_jids = @residual_contact_inboxes.select { |contact_inbox| contact_inbox.inbox_id == inbox.id }
                                             .reject { |contact_inbox| group_source?(contact_inbox.source_id) }
                                             .map(&:source_id)
    phone_jids = anchors.pluck(:phone_number).uniq.map { |phone| phone_jid(phone) }
    (phone_jids + residual_jids).uniq
  end

  def index_contact_lookup(inbox, contact)
    phone_number = phone_number_from_source(contact['phone_jid']) || phone_number_from_source(contact['jid'])
    name = contact['display_name'].to_s.strip
    @contact_names[phone_number] ||= name if phone_number.present? && human_name?(name, phone_number)
    return unless phone_number.present? && affected_anchor_phone_numbers.include?(phone_number)

    @resolved_alias_phones[[inbox.id, normalized_jid(contact['input_jid'])]] = phone_number
  end

  def repair_report
    {
      applied: false,
      account_id: account.id,
      requested_contact_ids: requested_contact_ids,
      detection_inbox_ids: @detection_inboxes.map(&:id),
      inbox_ids: @inboxes.map(&:id),
      affected_contact_ids: @affected_contact_ids,
      affected_conversations: @affected_anchors.sum { |anchor| anchor[:conversation_ids].size },
      contact_inboxes_to_reassign: @affected_anchors.size,
      aliases_to_quarantine: quarantinable_contact_inboxes.size,
      mappings: @affected_anchors.map { |anchor| mapping_report(anchor) }
    }
  end

  def mapping_report(anchor)
    {
      inbox_id: anchor[:inbox].id,
      contact_inbox_id: anchor[:contact_inbox].id,
      conversation_ids: anchor[:conversation_ids],
      from_contact_id: anchor[:original_contact_id],
      phone_number: anchor[:phone_number],
      contact_name: @contact_names[anchor[:phone_number]],
      existing_target_contact_id: account.contacts.find_by(phone_number: anchor[:phone_number])&.id
    }
  end

  def write_snapshot
    FileUtils.mkdir_p(resolved_snapshot_dir)
    path = resolved_snapshot_dir.join("account-#{account.id}-#{Time.current.utc.strftime('%Y%m%d%H%M%S')}.json")
    File.write(path, JSON.pretty_generate(snapshot_payload))
    File.chmod(0o600, path)
    path
  end

  def resolved_snapshot_dir
    Pathname.new(snapshot_dir.presence || Rails.root.join('tmp/whatsmeow_identity_repair'))
  end

  def snapshot_payload
    record_ids = snapshot_record_ids

    {
      generated_at: Time.current.utc.iso8601,
      account_id: account.id,
      contacts: account.contacts.where(id: record_ids[:contacts]).map { |contact| snapshot_contact(contact) },
      contact_inboxes: ContactInbox.where(id: record_ids[:contact_inboxes]).map { |item| snapshot_contact_inbox(item) },
      conversations: Conversation.where(id: record_ids[:conversations]).map { |conversation| snapshot_conversation(conversation) },
      message_senders: Message.where(conversation_id: record_ids[:conversations], sender_type: 'Contact').pluck(:id, :conversation_id, :sender_id)
    }
  end

  def snapshot_record_ids
    conversation_ids = @affected_anchors.flat_map { |anchor| anchor[:conversation_ids] }.uniq
    contact_inbox_ids = (@affected_anchors.pluck(:contact_inbox).map(&:id) + @residual_contact_inboxes.map(&:id)).uniq
    existing_target_ids = @affected_anchors.filter_map do |anchor|
      account.contacts.find_by(phone_number: anchor[:phone_number])&.id
    end

    {
      contacts: (@affected_contact_ids + existing_target_ids).uniq,
      contact_inboxes: contact_inbox_ids,
      conversations: conversation_ids
    }
  end

  def snapshot_contact(contact)
    contact.attributes.slice(
      'id', 'name', 'phone_number', 'additional_attributes', 'custom_attributes', 'email', 'identifier', 'contact_type', 'account_id'
    )
  end

  def snapshot_contact_inbox(contact_inbox)
    contact_inbox.attributes.slice('id', 'inbox_id', 'contact_id', 'source_id')
  end

  def snapshot_conversation(conversation)
    conversation.attributes.slice('id', 'inbox_id', 'contact_id', 'contact_inbox_id')
  end

  def apply_plan
    lock_repair_rows
    @affected_anchors.each { |anchor| apply_anchor(anchor) }
    apply_residual_contact_inboxes
    cleanup_affected_contacts
  end

  def lock_repair_rows
    account.contacts.where(id: repair_contact_ids).order(:id).lock.load
    ContactInbox.where(id: repair_contact_inbox_ids).order(:id).lock.load
    Conversation.where(id: repaired_conversation_ids).order(:id).lock.load
  end

  def repair_contact_ids
    target_ids = account.contacts.where(phone_number: affected_anchor_phone_numbers).pluck(:id)
    (@affected_contact_ids + target_ids).uniq
  end

  def repair_contact_inbox_ids
    (@affected_anchors.pluck(:contact_inbox).map(&:id) + @residual_contact_inboxes.map(&:id)).uniq
  end

  def repair_anchor_contact_inbox_ids
    @repair_anchor_contact_inbox_ids ||= @affected_anchors.pluck(:contact_inbox).map(&:id).uniq
  end

  def apply_anchor(anchor)
    contact = canonical_contact(anchor[:phone_number])
    contact_inbox = anchor[:contact_inbox]
    contact_inbox.update!(contact: contact) if contact_inbox.contact_id != contact.id

    Conversation.where(id: anchor[:conversation_ids]).find_each do |conversation|
      conversation.update!(contact: contact, contact_inbox: contact_inbox)
      conversation.messages.where(sender_type: 'Contact').where.not(sender_id: contact.id).find_each do |message|
        message.update!(sender: contact)
      end
    end

    @profile_syncs << [contact.id, anchor[:inbox].id, phone_jid(anchor[:phone_number])]
  end

  def canonical_contact(phone_number)
    @canonical_contacts[phone_number] ||= begin
      contact = account.contacts.find_by(phone_number: phone_number)
      contact ||= create_contact(phone_number)
      sync_canonical_contact(contact, phone_number)
      contact
    end
  end

  def create_contact(phone_number)
    contact = Contact.transaction(requires_new: true) do
      account.contacts.create!(name: @contact_names[phone_number].presence || phone_number, phone_number: phone_number)
    end
    @created_contact_ids << contact.id
    contact
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    account.contacts.find_by!(phone_number: phone_number)
  end

  def sync_canonical_contact(contact, phone_number)
    attributes = {}
    name = @contact_names[phone_number]
    attributes[:name] = name if name.present? && contact.name != name
    cleaned_attributes = (contact.additional_attributes || {}).except(*DIRECT_CONTACT_ATTRIBUTE_KEYS)
    attributes[:additional_attributes] = cleaned_attributes if cleaned_attributes != contact.additional_attributes
    contact.update!(attributes) if attributes.present?
  end

  def apply_residual_contact_inboxes
    @residual_contact_inboxes.each do |contact_inbox|
      next if group_source?(contact_inbox.source_id)

      phone_number = resolved_phone_number(contact_inbox)
      contact = @canonical_contacts[phone_number]
      contact ||= quarantine_contact(contact_inbox)
      contact_inbox.update!(contact: contact) if contact_inbox.contact_id != contact.id
    end
  end

  def quarantine_contact(contact_inbox)
    contact = account.contacts.create!(
      name: contact_inbox.source_id,
      additional_attributes: {
        whatsmeow_identity_quarantined: true,
        whatsmeow_source_id: contact_inbox.source_id
      }
    )
    @created_contact_ids << contact.id
    contact
  end

  def quarantinable_contact_inboxes
    @residual_contact_inboxes.reject do |contact_inbox|
      group_source?(contact_inbox.source_id) || resolved_phone_number(contact_inbox).present?
    end
  end

  def resolved_phone_number(contact_inbox)
    phone_number = phone_number_from_source(contact_inbox.source_id)
    return if phone_number == normalized_phone(contact_inbox.inbox.channel.phone_number)
    return phone_number if affected_anchor_phone_numbers.include?(phone_number)

    @resolved_alias_phones[[contact_inbox.inbox_id, normalized_jid(contact_inbox.source_id)]]
  end

  def affected_anchor_phone_numbers
    @affected_anchor_phone_numbers ||= @affected_anchors.pluck(:phone_number).uniq
  end

  def requested_contact_ids
    @requested_contact_ids ||= Array(contact_ids).filter_map { |contact_id| Integer(contact_id, exception: false) }.uniq
  end

  def cleanup_affected_contacts
    account.contacts.where(id: @affected_contact_ids).find_each do |contact|
      cleaned_attributes = (contact.additional_attributes || {}).except(*DIRECT_CONTACT_ATTRIBUTE_KEYS)
      contact.update!(additional_attributes: cleaned_attributes) if cleaned_attributes != contact.additional_attributes
    end
  end

  def enqueue_profile_syncs
    return enqueue_profile_sync_jobs unless async_queue_adapter?

    original_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :inline
    enqueue_profile_sync_jobs
  ensure
    ActiveJob::Base.queue_adapter = original_adapter if original_adapter
  end

  def enqueue_profile_sync_jobs
    @profile_syncs.uniq.each do |contact_id, target_inbox_id, source_id|
      Whatsmeow::ProfilePictureSyncJob.perform_later(contact_id, target_inbox_id, source_id, force: true)
    end
  end

  def async_queue_adapter?
    ActiveJob::Base.queue_adapter.is_a?(ActiveJob::QueueAdapters::AsyncAdapter)
  end

  def reconcile_post_commit
    @post_commit_reconciled_messages = 0
    3.times do
      reconcile_conversation_contacts
      repaired = reconcile_message_senders
      @post_commit_reconciled_messages += repaired
      break if repaired.zero? && sender_mismatch_count.zero?
    end
  end

  def reconcile_conversation_contacts
    repaired_conversation_ids.each do |conversation_id|
      conversation = Conversation.includes(:contact_inbox).find(conversation_id)
      next if conversation.contact_id == conversation.contact_inbox.contact_id

      conversation.update!(contact_id: conversation.contact_inbox.contact_id)
    end
  end

  def reconcile_message_senders
    repaired = 0
    Conversation.where(id: repaired_conversation_ids).find_each do |conversation|
      messages = conversation.messages.where(sender_type: 'Contact').where.not(sender_id: conversation.contact_id)
      messages.find_each do |message|
        message.update!(sender_id: conversation.contact_id)
        repaired += 1
      end
    end
    repaired
  end

  def sender_mismatch_count
    Conversation.where(id: repaired_conversation_ids).to_a.sum do |conversation|
      conversation.messages.where(sender_type: 'Contact').where.not(sender_id: conversation.contact_id).count
    end
  end

  def repaired_conversation_ids
    Conversation.where(contact_inbox_id: repair_anchor_contact_inbox_ids).pluck(:id)
  end

  def phone_number_from_source(source_id)
    value = source_id.to_s.strip.downcase
    return if unsupported_direct_source?(value)

    user, server = value.split('@', 2)
    return if server.present? && server != 's.whatsapp.net'

    digits = user.split(':').first.delete('^0-9')
    "+#{digits}" if digits.match?(/\A[1-9]\d{9,14}\z/)
  end

  def unsupported_direct_source?(source_id)
    source_id.blank? || source_id.match?(/@(lid|g\.us|newsletter)/)
  end

  def normalized_phone(value)
    digits = value.to_s.delete('^0-9')
    "+#{digits}" if digits.match?(/\A[1-9]\d{9,14}\z/)
  end

  def phone_jid(phone_number)
    "#{phone_number.delete('^0-9')}@s.whatsapp.net"
  end

  def normalized_jid(source_id)
    user, server = source_id.to_s.strip.downcase.split('@', 2)
    return source_id.to_s.strip.downcase if server.blank?

    "#{user.split(':').first}@#{server}"
  end

  def group_source?(source_id)
    source_id.to_s.downcase.include?('@g.us')
  end

  def human_name?(name, phone_number)
    name.present? && name != phone_number && !name.match?(/\A\+?\d+\z/) && !name.match?(/@(lid|s\.whatsapp\.net|g\.us)\z/i)
  end
end
# rubocop:enable Metrics/ClassLength
