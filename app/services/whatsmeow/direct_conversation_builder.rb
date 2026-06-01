class Whatsmeow::DirectConversationBuilder
  pattr_initialize [:inbox!, :params!]

  def perform
    raise ArgumentError, 'Missing WhatsApp participant target' if source_ids.blank?

    contact_inbox = ::ContactInboxSourceIdResolver.new(
      source_ids: source_ids,
      inbox: inbox,
      contact_attributes: contact_attributes
    ).perform

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
    attributes[:additional_attributes] = (contact.additional_attributes || {}).merge('whatsmeow_group_participant' => true)
    contact.update!(attributes) if attributes.present?
    ::Avatar::AvatarFromUrlJob.perform_later(contact, profile_picture_url) if profile_picture_url.present? && !contact.avatar.attached?
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
      additional_attributes: {
        whatsmeow_group_participant: true
      }
    }
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
