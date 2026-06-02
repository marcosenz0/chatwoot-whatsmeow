class Whatsmeow::GroupConversationBuilder
  pattr_initialize [:inbox!, :params!]

  def perform
    raise ArgumentError, 'Missing WhatsApp group target' if group_jid.blank?

    contact_inbox = ::ContactInboxSourceIdResolver.new(
      source_ids: [group_jid],
      inbox: inbox,
      contact_attributes: contact_attributes
    ).perform

    sync_group_profile(contact_inbox.contact)
    find_or_create_conversation(contact_inbox)
  end

  private

  def find_or_create_conversation(contact_inbox)
    conversations = ::Conversation.where(
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      contact_id: contact_inbox.contact_id
    )
    conversation = inbox.lock_to_single_conversation ? conversations.last : conversations.where.not(status: :resolved).last
    conversation || ::Conversation.create!(
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      contact_id: contact_inbox.contact_id,
      contact_inbox_id: contact_inbox.id
    )
  end

  def sync_group_profile(contact)
    attributes = {}
    attributes[:name] = group_name if should_update_name?(contact)
    attributes[:phone_number] = nil if contact.phone_number.present?
    attributes[:additional_attributes] = (contact.additional_attributes || {}).merge(group_additional_attributes.stringify_keys)
    contact.update!(attributes) if attributes.present?

    if profile_picture_url.present?
      ::Avatar::AvatarFromUrlJob.perform_later(contact, profile_picture_url, force: !contact.avatar.attached?)
    elsif !contact.avatar.attached?
      ::Whatsmeow::ProfilePictureSyncJob.perform_later(contact.id, inbox.id, group_jid)
    end
  end

  def contact_attributes
    {
      name: group_name,
      phone_number: nil,
      avatar_url: profile_picture_url,
      additional_attributes: group_additional_attributes
    }
  end

  def group_additional_attributes
    {
      whatsmeow_group: true,
      whatsmeow_group_jid: group_jid,
      whatsmeow_group_participant_count: participant_count
    }.compact_blank
  end

  def should_update_name?(contact)
    group_name.present? && (contact.name.blank? || jid_like?(contact.name))
  end

  def group_jid
    @group_jid ||= params[:group_jid].to_s.strip.presence
  end

  def group_name
    @group_name ||= params[:group_name].presence || group_jid
  end

  def profile_picture_url
    @profile_picture_url ||= params[:profile_picture_url].presence
  end

  def participant_count
    @participant_count ||= params[:participant_count].presence
  end

  def jid_like?(value)
    value.to_s.include?('@g.us') || value.to_s.include?('@s.whatsapp.net') || value.to_s.include?('@lid')
  end
end
