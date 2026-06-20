require 'base64'
require 'stringio'

# rubocop:disable Metrics/ClassLength
class Whatsmeow::IncomingMessageService
  pattr_initialize [:inbox!, :params!]

  def perform
    return if handle_already_imported_message
    return if ignored_newsletter?

    set_contact
    set_message_sender
    set_conversation
    @message = @conversation.messages.build(
      content: message_content,
      account_id: @inbox.account_id,
      inbox_id: @inbox.id,
      message_type: outgoing_echo? ? :outgoing : :incoming,
      status: outgoing_echo? ? :delivered : :sent,
      sender: @message_sender,
      source_id: params[:message_id],
      content_attributes: message_content_attributes
    )
    attach_files
    attach_contacts
    @message.save!
    Whatsmeow::AttachmentRetentionScheduler.maybe_enqueue
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
    imported_message.present?
  end

  def handle_already_imported_message
    return false unless message_already_imported?

    edited_content = message_content.to_s
    return true if edited_content.blank? || imported_message.content.to_s == edited_content

    Whatsmeow::EditMessageService.apply_incoming(
      inbox: @inbox,
      params: params.merge(edited_content: edited_content)
    )
    true
  end

  def imported_message
    return if params[:message_id].blank?

    @imported_message ||= @inbox.messages.find_by(source_id: params[:message_id])
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
    ].compact_blank.reject { |source_id| group_source(source_id) }.uniq
  end

  def group_source_ids
    [group_jid].compact_blank.uniq
  end

  def participant_source_ids
    [
      participant_phone_source_id,
      params[:participant_jid],
      params[:participant_lid_jid],
      params[:sender_alt]
    ].compact_blank.reject { |source_id| group_source(source_id) }.uniq
  end

  def all_payload_source_ids
    [
      params[:sender],
      params[:sender_alt],
      params[:chat],
      params[:recipient_alt],
      params[:group_jid],
      params[:participant_jid],
      params[:participant_lid_jid]
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
    @group_jid ||= canonical_group_source(params[:group_jid]) ||
                   canonical_group_source(params[:chat]) ||
                   canonical_group_source(params[:sender])
  end

  def group_source(identifier)
    identifier.to_s.include?('@g.us') ? identifier : nil
  end

  def canonical_group_source(identifier)
    source = group_source(identifier)
    return if source.blank?

    user = source.to_s.split('@').first.split(':').first
    "#{user}@g.us"
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

    contact_inbox = isolate_contact_inbox(contact_inbox, contact_attributes) if should_isolate_contact_inbox?(contact_inbox)
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
    contact_inbox = isolate_contact_inbox(contact_inbox, participant_contact_attributes) if should_isolate_contact_inbox?(contact_inbox)
    contact = contact_inbox.contact
    sync_contact_profile(contact, participant_contact_attributes, params[:participant_profile_picture_url], params[:participant_jid])
    contact
  end

  def should_isolate_contact_inbox?(contact_inbox)
    group_profile?(contact_inbox.contact) && (!group_message? || contact_inbox.source_id != group_jid)
  end

  def isolate_contact_inbox(contact_inbox, attributes_for_contact)
    contact = find_or_create_direct_contact(attributes_for_contact, contact_inbox.contact_id)
    contact_inbox.update!(contact: contact)
    contact_inbox
  end

  def find_or_create_direct_contact(attributes_for_contact, excluded_contact_id)
    existing_contact = find_existing_direct_contact(attributes_for_contact[:phone_number], excluded_contact_id)
    return existing_contact if existing_contact

    @inbox.account.contacts.create!(
      name: attributes_for_contact[:name] || ::Haikunator.haikunate(1000),
      phone_number: attributes_for_contact[:phone_number],
      additional_attributes: attributes_for_contact[:additional_attributes]
    )
  end

  def find_existing_direct_contact(phone, excluded_contact_id)
    return if phone.blank?

    @inbox.account.contacts.where(phone_number: phone)
          .where.not(id: excluded_contact_id)
          .find { |contact| !group_profile?(contact) }
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
    @contact.with_lock do
      @conversation = if @inbox.lock_to_single_conversation
                        inbox_contact_conversations.last
                      else
                        inbox_contact_conversations.where
                                                   .not(status: :resolved).last
                      end
      @conversation ||= ::Conversation.create!(conversation_params)
    end
  end

  def inbox_contact_conversations
    conversation_filters = {
      account_id: @inbox.account_id,
      inbox_id: @inbox.id,
      contact_id: @contact.id
    }
    conversation_filters[:contact_inbox_id] = @contact_inbox.id unless group_message?

    ::Conversation.where(conversation_filters)
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
        whatsmeow_group_participant: true,
        whatsmeow_participant_jid: params[:participant_jid],
        whatsmeow_participant_lid_jid: params[:participant_lid_jid],
        whatsmeow_participant_phone: participant_phone_number
      }.compact_blank
    }
  end

  def sync_contact_profile(contact, attributes_for_contact, avatar_url, source_label)
    attributes = contact_profile_attributes(contact, attributes_for_contact)
    contact.update!(attributes) if attributes.present?
    sync_contact_avatar(contact, avatar_url, source_label)
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    Rails.logger.info("Whatsmeow: skipped contact profile sync for inbox #{@inbox.id} and sender #{source_label}")
  end

  def sync_contact_avatar(contact, avatar_url, source_label)
    if avatar_url.present?
      ::Avatar::AvatarFromUrlJob.perform_later(contact, avatar_url, force: force_group_avatar_sync?(contact))
      return
    end

    return unless should_refresh_contact_avatar?(contact)

    ::Whatsmeow::ProfilePictureSyncJob.perform_later(contact.id, @inbox.id, source_label)
  end

  def force_group_avatar_sync?(contact)
    group_profile?(contact) && !contact.avatar.attached?
  end

  def should_refresh_contact_avatar?(contact)
    return true unless contact.avatar.attached?

    checked_at = (contact.additional_attributes || {})['whatsmeow_profile_picture_checked_at']
    checked_at.blank? || Time.zone.parse(checked_at) < 24.hours.ago
  rescue ArgumentError
    true
  end

  def contact_profile_attributes(contact, attributes_for_contact)
    attributes = {}
    number = attributes_for_contact[:phone_number]
    name = attributes_for_contact[:name]
    additional_attributes = attributes_for_contact[:additional_attributes]

    attributes[:phone_number] = nil if clear_group_phone?(contact, attributes_for_contact)
    attributes[:phone_number] = number if should_update_contact_phone?(contact, number, attributes_for_contact)
    attributes[:name] = name if should_update_contact_name?(contact, name)
    attributes[:additional_attributes] = merged_additional_attributes(contact, additional_attributes) if additional_attributes.present?
    attributes
  end

  def should_update_contact_name?(contact, name)
    return false if name.blank?
    return true if contact.name.blank?
    return true if contact.name == contact.phone_number
    return true if contact.name.include?('@lid') || contact.name.include?('@s.whatsapp.net') || contact.name.include?('@g.us')

    false
  end

  def should_update_contact_phone?(contact, number, attributes_for_contact)
    return false if number.blank?
    return false if group_profile?(contact) || group_profile_attributes?(attributes_for_contact)

    contact.phone_number.blank? || contact.name == number || contact.name.to_s.include?('@lid')
  end

  def group_profile?(contact)
    additional_attributes = contact.additional_attributes || {}
    additional_attributes.fetch('whatsmeow_group', false) || additional_attributes.fetch(:whatsmeow_group, false)
  end

  def group_profile_attributes?(attributes_for_contact)
    additional_attributes = attributes_for_contact[:additional_attributes]
    additional_attributes&.fetch(:whatsmeow_group, false) || additional_attributes&.fetch('whatsmeow_group', false)
  end

  def clear_group_phone?(contact, attributes_for_contact)
    group_profile_attributes?(attributes_for_contact) && contact.phone_number.present?
  end

  def merged_additional_attributes(contact, additional_attributes)
    new_attributes = additional_attributes.stringify_keys
    attributes = (contact.additional_attributes || {}).merge(new_attributes)
    attributes = attributes.except('whatsmeow_group_participant') if new_attributes['whatsmeow_group']
    attributes
  end

  def message_content_attributes
    attributes = {}
    attributes[:external_echo] = true if outgoing_echo?
    attributes.merge!(group_content_attributes) if group_message?
    attributes.merge!(quoted_content_attributes) if quoted_message?
    attributes[:whatsmeow_contacts] = contact_params if contact_message?
    attributes
  end

  def message_content
    params[:content].presence || contact_message_content
  end

  def contact_message_content
    return if contact_params.blank?

    first_contact = contact_params.first
    name = contact_display_name(first_contact)
    contact_params.one? ? "Contato: #{name}" : "#{contact_params.size} contatos compartilhados"
  end

  def group_content_attributes
    {
      whatsmeow_group: true,
      group_jid: group_jid,
      group_name: params[:group_name],
      participant_jid: params[:participant_jid],
      participant_lid_jid: params[:participant_lid_jid],
      participant_name: params[:participant_name],
      participant_phone: participant_phone_number
    }.compact_blank
  end

  def quoted_message?
    params[:quoted_message_id].present?
  end

  def quoted_content_attributes
    quoted_message = {
      source_id: params[:quoted_message_id],
      participant: params[:quoted_participant],
      content: params[:quoted_content],
      file_type: params[:quoted_file_type]
    }.compact_blank

    {
      in_reply_to_external_id: params[:quoted_message_id],
      whatsmeow_quoted_message: quoted_message
    }.compact_blank
  end

  def attach_files
    attachment_params.each do |attachment|
      data = Base64.decode64(attachment[:data_base64].to_s)
      next if data.blank?

      @message.attachments.new(
        account_id: @message.account_id,
        file_type: normalized_file_type(attachment[:file_type]),
        meta: attachment_meta(attachment),
        file: {
          io: StringIO.new(data),
          filename: attachment[:file_name].presence || default_file_name(attachment[:file_type]),
          content_type: normalized_content_type(attachment[:content_type])
        }
      )
    end
  end

  def attach_contacts
    contact_params.each do |contact|
      @message.attachments.new(
        account_id: @message.account_id,
        file_type: :contact,
        fallback_title: contact_phone_number(contact),
        meta: contact_attachment_meta(contact)
      )
    end
  end

  def attachment_params
    Array(params[:attachments]).filter_map do |attachment|
      next unless attachment.respond_to?(:with_indifferent_access)

      attachment.with_indifferent_access
    end
  end

  def attachment_meta(attachment)
    meta = attachment[:meta].respond_to?(:to_h) ? attachment[:meta].to_h.with_indifferent_access.compact_blank : {}
    return meta unless whatsmeow_sticker_meta?(meta)

    meta.merge(sticker_attachment_meta(attachment))
  end

  def whatsmeow_sticker_meta?(meta)
    ActiveModel::Type::Boolean.new.cast(meta[:whatsmeow_sticker] || meta[:whatsmeowSticker])
  end

  def sticker_attachment_meta(attachment)
    content_type = normalized_content_type(attachment[:content_type])
    content_type = 'image/webp' if content_type == 'application/octet-stream'

    {
      file_name: attachment[:file_name],
      content_type: content_type,
      file_size: attachment[:file_size]
    }.compact_blank
  end

  def contact_params
    @contact_params ||= Array(params[:contacts]).filter_map do |contact|
      next unless contact.respond_to?(:with_indifferent_access)

      contact.with_indifferent_access
    end
  end

  def contact_message?
    contact_params.present?
  end

  def contact_display_name(contact)
    [
      contact[:display_name],
      contact[:full_name],
      "#{contact[:first_name]} #{contact[:last_name]}".strip,
      contact[:organization],
      contact_phone_number(contact)
    ].compact_blank.first
  end

  def contact_phone_number(contact)
    contact[:phone_number].presence || contact[:whatsapp_id].presence || contact[:jid].to_s.split('@').first.presence
  end

  def contact_attachment_meta(contact)
    {
      display_name: contact[:display_name],
      full_name: contact[:full_name],
      first_name: contact[:first_name],
      last_name: contact[:last_name],
      phone_number: contact_phone_number(contact),
      whatsapp_id: contact[:whatsapp_id],
      jid: contact[:jid],
      organization: contact[:organization],
      title: contact[:title],
      email: contact[:email],
      website: contact[:website],
      note: contact[:note],
      category: contact[:category],
      avatar_url: contact[:avatar_url],
      profile_picture_url: contact[:profile_picture_url],
      business_profile: contact[:business_profile],
      vcard: contact[:vcard]
    }.compact_blank
  end

  def normalized_file_type(file_type)
    return file_type if Attachment.file_types.key?(file_type.to_s)

    'file'
  end

  def normalized_content_type(content_type)
    value = content_type.to_s.split(';').first.strip.downcase
    return 'application/octet-stream' if value.blank?
    return 'audio/ogg' if value == 'audio/opus'

    value
  end

  def default_file_name(file_type)
    extension = {
      'image' => 'jpg',
      'audio' => 'ogg',
      'video' => 'mp4'
    }.fetch(file_type.to_s, 'bin')

    "whatsapp-attachment.#{extension}"
  end

  def ignored_newsletter?
    @inbox.channel.try(:ignore_newsletters) && all_payload_source_ids.any? { |source_id| newsletter_source?(source_id) }
  end

  def newsletter_source?(source_id)
    source_id.to_s.downcase.include?('@newsletter')
  end
end
# rubocop:enable Metrics/ClassLength
