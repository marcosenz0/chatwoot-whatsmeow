class ConversationBuilder
  pattr_initialize [:params!, :contact_inbox!]

  def perform
    if @contact_inbox.inbox.channel_type == 'Channel::Whatsmeow' && whatsmeow_phone_number.present?
      return build_whatsmeow_direct_conversation
    end

    look_up_existing_conversation || create_new_conversation
  end

  private

  def build_whatsmeow_direct_conversation
    inbox = @contact_inbox.inbox
    inbox.with_lock do
      reconcile_whatsmeow_phone_alias(inbox)
      @contact_inbox.conversations.where.not(status: :resolved).last || look_up_existing_conversation || create_new_conversation
    end
  end

  def reconcile_whatsmeow_phone_alias(inbox)
    alternate = Whatsmeow::VerifiedPhoneAlias.new(inbox: inbox, phone_number: whatsmeow_phone_number, peer_lid: nil).perform
    return if alternate.blank?

    @contact_inbox = Whatsmeow::ContactIdentityResolver.new(
      inbox: inbox, phone_number: "+#{alternate.split('@').first}", source_ids: [], contact_attributes: {},
      verified_phone_alias: @contact_inbox.source_id
    ).perform
  end

  def whatsmeow_phone_number
    digits = @contact_inbox.source_id.to_s[/\A([1-9]\d{9,14})@s\.whatsapp\.net\z/, 1]
    "+#{digits}" if digits
  end

  def look_up_existing_conversation
    return unless @contact_inbox.inbox.lock_to_single_conversation?

    @contact_inbox.conversations.last
  end

  def create_new_conversation
    ::Conversation.create!(conversation_params)
  end

  def conversation_params
    additional_attributes = params[:additional_attributes]&.permit! || {}
    custom_attributes = params[:custom_attributes]&.permit! || {}
    status = params[:status].present? ? { status: params[:status] } : {}

    # TODO: temporary fallback for the old bot status in conversation, we will remove after couple of releases
    # commenting this out to see if there are any errors, if not we can remove this in subsequent releases
    # status = { status: 'pending' } if status[:status] == 'bot'
    {
      account_id: @contact_inbox.inbox.account_id,
      inbox_id: @contact_inbox.inbox_id,
      contact_id: @contact_inbox.contact_id,
      contact_inbox_id: @contact_inbox.id,
      additional_attributes: additional_attributes,
      custom_attributes: custom_attributes,
      snoozed_until: params[:snoozed_until],
      assignee_id: params[:assignee_id],
      team_id: params[:team_id]
    }.merge(status)
  end
end
