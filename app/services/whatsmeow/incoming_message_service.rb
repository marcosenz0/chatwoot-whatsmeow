class Whatsmeow::IncomingMessageService
  pattr_initialize [:inbox!, :params!]

  def perform
    return if message_already_imported?

    set_contact
    set_conversation
    @message = @conversation.messages.create!(
      content: params[:content],
      account_id: @inbox.account_id,
      inbox_id: @inbox.id,
      message_type: outgoing_echo? ? :outgoing : :incoming,
      status: outgoing_echo? ? :delivered : :sent,
      sender: outgoing_echo? ? nil : @contact,
      source_id: params[:message_id],
      content_attributes: outgoing_echo? ? { external_echo: true } : {}
    )
  end

  private

  def outgoing_echo?
    ActiveModel::Type::Boolean.new.cast(params[:from_me])
  end

  def message_already_imported?
    params[:message_id].present? && Message.exists?(inbox_id: @inbox.id, source_id: params[:message_id])
  end

  def sender_identifier
    params[:sender].presence || params[:sender_alt].presence || params[:chat].presence || params[:recipient_alt].presence
  end

  def source_ids
    @source_ids ||= [
      phone_source_id,
      params[:sender],
      params[:sender_alt],
      params[:chat],
      params[:recipient_alt]
    ].compact_blank.uniq
  end

  def phone_number
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
    sync_contact_profile
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
    {
      name: params[:sender_name].presence || phone_number || sender_identifier,
      phone_number: phone_number
    }
  end

  def sync_contact_profile
    attributes = {}
    attributes[:phone_number] = phone_number if phone_number.present? && @contact.phone_number.blank?
    attributes[:name] = contact_attributes[:name] if should_update_contact_name?

    @contact.update!(attributes) if attributes.present?
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    Rails.logger.info("Whatsmeow: skipped contact profile sync for inbox #{@inbox.id} and sender #{sender_identifier}")
  end

  def should_update_contact_name?
    return false if contact_attributes[:name].blank?
    return true if @contact.name.blank?
    return true if @contact.name == @contact.phone_number
    return true if @contact.name.include?('@lid') || @contact.name.include?('@s.whatsapp.net')

    false
  end
end
