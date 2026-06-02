class Whatsmeow::DirectConversationBuilder
  pattr_initialize [:inbox!, :params!]

  def perform
    raise ArgumentError, 'Missing WhatsApp participant target' if source_ids.blank?

    contact_inbox = ::ContactInboxSourceIdResolver.new(
      source_ids: source_ids,
      inbox: inbox,
      contact_attributes: contact_attributes
    ).perform

    contact_inbox = isolate_group_contact_inbox(contact_inbox) if group_profile?(contact_inbox.contact)
    sync_contact_profile(contact_inbox.contact)
    find_or_create_conversation(contact_inbox)
  end

  private

  def find_or_create_conversation(contact_inbox)
    conversations = ::Conversation.where(
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      contact_id: contact_inbox.contact_id,
      contact_inbox_id: contact_inbox.id
    )
    conversation = inbox.lock_to_single_conversation ? conversations.last : conversations.where.not(status: :resolved).last
    conversation || ::Conversation.create!(
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      contact_id: contact_inbox.contact_id,
      contact_inbox_id: contact_inbox.id
    )
  end

  def sync_contact_profile(contact)
    attributes = {}
    attributes[:name] = display_name if should_update_name?(contact)
    attributes[:phone_number] = phone_number if phone_number.present? && contact.phone_number.blank?
    attributes[:additional_attributes] = (contact.additional_attributes || {}).merge(participant_additional_attributes)
    contact.update!(attributes) if attributes.present?
    if profile_picture_url.present?
      ::Avatar::AvatarFromUrlJob.perform_later(contact, profile_picture_url)
    else
      ::Whatsmeow::ProfilePictureSyncJob.perform_later(contact.id, inbox.id, participant_jid)
    end
  end

  def isolate_group_contact_inbox(contact_inbox)
    group_contact = contact_inbox.contact
    clear_group_phone(group_contact)
    direct_contact = find_or_create_direct_contact(group_contact.id)

    contact_inbox.update!(contact: direct_contact)
    move_direct_conversations(contact_inbox, group_contact, direct_contact)
    contact_inbox.reload
  end

  def move_direct_conversations(contact_inbox, group_contact, direct_contact)
    contact_inbox.conversations.where(contact_id: group_contact.id).find_each do |conversation|
      conversation.update!(contact: direct_contact)
    end
  end

  def clear_group_phone(contact)
    attributes = {}
    attributes[:phone_number] = nil if phone_number.present? && contact.phone_number == phone_number
    attributes[:additional_attributes] = (contact.additional_attributes || {}).except('whatsmeow_group_participant')
    contact.update!(attributes) if attributes.present?
  end

  def find_or_create_direct_contact(excluded_contact_id)
    existing_contact = find_existing_direct_contact(excluded_contact_id)
    return existing_contact if existing_contact

    inbox.account.contacts.create!(
      name: contact_attributes[:name] || ::Haikunator.haikunate(1000),
      phone_number: phone_number,
      additional_attributes: contact_attributes[:additional_attributes]
    )
  end

  def find_existing_direct_contact(excluded_contact_id)
    return if phone_number.blank?

    inbox.account.contacts.where(phone_number: phone_number)
         .where.not(id: excluded_contact_id)
         .find { |contact| !group_profile?(contact) }
  end

  def group_profile?(contact)
    additional_attributes = contact.additional_attributes || {}
    additional_attributes.fetch('whatsmeow_group', false) || additional_attributes.fetch(:whatsmeow_group, false)
  end

  def should_update_name?(contact)
    display_name.present? && (contact.name.blank? || contact.name == contact.phone_number || jid_like?(contact.name))
  end

  def source_ids
    @source_ids ||= [phone_source_id, participant_jid].compact_blank.reject { |source_id| group_jid?(source_id) }.uniq
  end

  def contact_attributes
    {
      name: display_name.presence || phone_number.presence || participant_jid,
      phone_number: phone_number,
      avatar_url: profile_picture_url,
      additional_attributes: participant_additional_attributes
    }
  end

  def participant_additional_attributes
    {
      whatsmeow_group_participant: true,
      whatsmeow_participant_jid: participant_jid,
      whatsmeow_participant_lid_jid: participant_lid_jid,
      whatsmeow_participant_phone: phone_number
    }.compact_blank
  end

  def display_name
    @display_name ||= params[:participant_name].presence
  end

  def phone_number
    @phone_number ||= params[:participant_phone].presence || extract_phone_number(participant_jid)
  end

  def phone_source_id
    return if phone_number.blank?

    "#{phone_number.delete('+')}@s.whatsapp.net"
  end

  def participant_jid
    @participant_jid ||= params[:participant_jid].presence
  end

  def participant_lid_jid
    @participant_lid_jid ||= params[:participant_lid_jid].presence
  end

  def profile_picture_url
    @profile_picture_url ||= params[:profile_picture_url].presence
  end

  def extract_phone_number(identifier)
    return if identifier.blank?

    server = identifier.to_s.split('@').second
    return if server == 'lid'

    digits = identifier.to_s.split('@').first.split(':').first.delete('^0-9')
    return unless digits.match?(/\A[1-9]\d{1,14}\z/)

    "+#{digits}"
  end

  def group_jid?(identifier)
    identifier.to_s.downcase.include?('@g.us')
  end

  def jid_like?(value)
    value.to_s.include?('@s.whatsapp.net') || value.to_s.include?('@lid') || value.to_s.include?('@g.us')
  end
end
