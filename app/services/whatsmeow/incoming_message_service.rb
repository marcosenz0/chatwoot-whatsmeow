# rubocop:disable Metrics/ClassLength
class Whatsmeow::IncomingMessageService
  pattr_initialize [:inbox!, :params!]

  def perform
    return if message_already_imported?
    return if ignored_newsletter?

    set_contact
    set_message_sender
    set_conversation
    @message = @conversation.messages.create!(
      content: params[:content],
      account_id: @inbox.account_id,
      inbox_id: @inbox.id,
      message_type: outgoing_echo? ? :outgoing : :incoming,
      status: outgoing_echo? ? :delivered : :sent,
      sender: @message_sender,
      source_id: params[:message_id],
      content_attributes: message_content_attributes
    )
  end

  private

  def boolean_param(key)
    ActiveModel::Type::Boolean.new.cast(params[key])
  end

  def outgoing_echo?
    boolean_param(:from_me)
  end

  def group_message?
    boolean_param(:is_group)
  end

  def message_already_imported?
    params[:message_id].present? && Message.exists?(inbox_id: @inbox.id, source_id: params[:message_id])
  end

  def sender_identifier
    return group_jid if group_message?

    params[:sender].presence || params[:sender_alt].presence || params[:chat].presence || params[:recipient_alt].presence
  end

  def source_ids
    @source_ids ||= group_message? ? group_source_ids : direct_source_ids
  end

  def direct_source_ids
    [
      phone_source_id,
      params[:sender],
      params[:sender_alt],
      params[:chat],
      params[:recipient_alt]
    ].compact_blank.uniq
  end

  def group_source_ids
    [
      group_jid,
      params[:chat]
    ].compact_blank.uniq
  end

  def participant_source_ids
    [
      participant_phone_source_id,
      params[:participant_jid],
      params[:sender_alt],
      params[:sender]
    ].compact_blank.uniq
  end

  def all_payload_source_ids
    [
      params[:sender],
      params[:sender_alt],
      params[:chat],
      params[:recipient_alt],
      params[:group_jid],
      params[:participant_jid]
    ].compact_blank.uniq
  end

  def phone_number
    return if group_message?

    @phone_number ||= params[:sender_phone].presence ||
                      extract_phone_number(params[:sender]) ||
                      extract_phone_number(params[:sender_alt]) ||
                      extract_phone_number(params[:chat]) ||
                      extract_phone_number(params[:recipient_alt])
  end

  def phone_source_id
    return if phone_number.blank?

    "#{phone_number.delete('+')}@s.whatsapp.net"
  end

  def participant_phone_number
    @participant_phone_number ||= params[:participant_phone].presence ||
                                  extract_phone_number(params[:participant_jid]) ||
                                  extract_phone_number(params[:sender_alt]) ||
                                  extract_phone_number(params[:sender])
  end

  def participant_phone_source_id
    return if participant_phone_number.blank?

    "#{participant_phone_number.delete('+')}@s.whatsapp.net"
  end

  def group_jid
    @group_jid ||= params[:group_jid].presence || group_source(params[:chat]) || group_source(params[:sender])
  end

  def group_source(identifier)
    identifier.to_s.include?('@g.us') ? identifier : nil
  end

  def extract_phone_number(identifier)
    return if identifier.blank?

    server = identifier.to_s.split('@').second
    return if server == 'lid'

    raw_num = identifier.to_s.split('@').first.split(':').first
    digits = raw_num.delete('^0-9')
    return unless digits.match?(/\A[1-9]\d{1,14}\z/)

    "+#{digits}"
  end

  def set_contact
    contact_inbox = ::ContactInboxSourceIdResolver.new(
      source_ids: source_ids.presence || [sender_identifier],
      inbox: @inbox,
      contact_attributes: contact_attributes
    ).perform

    @contact_inbox = contact_inbox
    @contact = contact_inbox.contact
    sync_contact_profile(@contact, contact_attributes, params[:profile_picture_url], sender_identifier)
  end

  def set_message_sender
    @message_sender = nil
    return if outgoing_echo?

    @message_sender = group_message? ? participant_contact : @contact
  end

  def participant_contact
    contact_inbox = ::ContactInboxSourceIdResolver.new(
      source_ids: participant_source_ids.presence || [params[:participant_jid], params[:sender]].compact_blank,
      inbox: @inbox,
      contact_attributes: participant_contact_attributes
    ).perform
    contact = contact_inbox.contact
    sync_contact_profile(contact, participant_contact_attributes, params[:participant_profile_picture_url], params[:participant_jid])
    contact
  end

  def conversation_params
    {
      account_id: @inbox.account_id,
      inbox_id: @inbox.id,
      contact_id: @contact.id,
      contact_inbox_id: @contact_inbox.id
    }
  end

  def set_conversation
    @conversation = if @inbox.lock_to_single_conversation
                      inbox_contact_conversations.last
                    else
                      inbox_contact_conversations.where
                                                 .not(status: :resolved).last
                    end
    return if @conversation

    @conversation = ::Conversation.create!(conversation_params)
  end

  def inbox_contact_conversations
    ::Conversation.where(
      account_id: @inbox.account_id,
      inbox_id: @inbox.id,
      contact_id: @contact.id
    )
  end

  def contact_attributes
    return group_contact_attributes if group_message?

    {
      name: phone_number || params[:sender_name].presence || sender_identifier,
      phone_number: phone_number
    }
  end

  def group_contact_attributes
    {
      name: params[:group_name].presence || sender_identifier,
      phone_number: nil,
      additional_attributes: {
        whatsmeow_group: true,
        whatsmeow_group_jid: group_jid
      }
    }
  end

  def participant_contact_attributes
    {
      name: params[:participant_name].presence || participant_phone_number || params[:participant_jid].presence || params[:sender].presence,
      phone_number: participant_phone_number,
      additional_attributes: {
        whatsmeow_group_participant: true
      }
    }
  end

  def sync_contact_profile(contact, attributes_for_contact, avatar_url, source_label)
    attributes = contact_profile_attributes(contact, attributes_for_contact)
    contact.update!(attributes) if attributes.present?
    ::Avatar::AvatarFromUrlJob.perform_later(contact, avatar_url) if avatar_url.present?
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    Rails.logger.info("Whatsmeow: skipped contact profile sync for inbox #{@inbox.id} and sender #{source_label}")
  end

  def contact_profile_attributes(contact, attributes_for_contact)
    attributes = {}
    number = attributes_for_contact[:phone_number]
    name = attributes_for_contact[:name]
    additional_attributes = attributes_for_contact[:additional_attributes]

    attributes[:phone_number] = number if should_update_contact_phone?(contact, number)
    attributes[:name] = name if should_update_contact_name?(contact, name)
    attributes[:additional_attributes] = (contact.additional_attributes || {}).merge(additional_attributes) if additional_attributes.present?
    attributes
  end

  def should_update_contact_name?(contact, name)
    return false if name.blank?
    return true if contact.name.blank?
    return true if contact.name == contact.phone_number
    return true if contact.name.include?('@lid') || contact.name.include?('@s.whatsapp.net') || contact.name.include?('@g.us')

    false
  end

  def should_update_contact_phone?(contact, number)
    return false if number.blank?

    contact.phone_number.blank? || contact.name == number || contact.name.to_s.include?('@lid')
  end

  def message_content_attributes
    attributes = {}
    attributes[:external_echo] = true if outgoing_echo?
    attributes.merge!(group_content_attributes) if group_message?
    attributes
  end

  def group_content_attributes
    {
      whatsmeow_group: true,
      group_jid: group_jid,
      group_name: params[:group_name],
      participant_jid: params[:participant_jid],
      participant_name: params[:participant_name],
      participant_phone: participant_phone_number
    }.compact_blank
  end

  def ignored_newsletter?
    @inbox.channel.try(:ignore_newsletters) && all_payload_source_ids.any? { |source_id| newsletter_source?(source_id) }
  end

  def newsletter_source?(source_id)
    source_id.to_s.downcase.include?('@newsletter')
  end
end
# rubocop:enable Metrics/ClassLength
