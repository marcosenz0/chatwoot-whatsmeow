class Whatsmeow::IncomingMessageService
  pattr_initialize [:inbox!, :params!]

  def perform
    set_contact
    set_conversation
    @message = @conversation.messages.create!(
      content: params[:content],
      account_id: @inbox.account_id,
      inbox_id: @inbox.id,
      message_type: :incoming,
      sender: @contact,
      source_id: params[:message_id]
    )
  end

  private

  def phone_number
    # sender looks like "5511999999999@s.whatsapp.net" or "5511999999999"
    # phone number needs to be normalized to "+5511999999999"
    raw_num = params[:sender].split('@').first
    raw_num.start_with?('+') ? raw_num : "+#{raw_num}"
  end

  def set_contact
    contact_inbox = ::ContactInboxWithContactBuilder.new(
      source_id: params[:sender],
      inbox: @inbox,
      contact_attributes: contact_attributes
    ).perform

    @contact_inbox = contact_inbox
    @contact = contact_inbox.contact
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
                      @contact_inbox.conversations.last
                    else
                      @contact_inbox.conversations.where
                                    .not(status: :resolved).last
                    end
    return if @conversation

    @conversation = ::Conversation.create!(conversation_params)
  end

  def contact_attributes
    {
      name: phone_number,
      phone_number: phone_number
    }
  end
end
