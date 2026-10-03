class Api::V1::Accounts::WhatsmeowDeletedMessagesController < Api::V1::Accounts::BaseController
  def index
    messages = visible_messages
    messages = messages.where(inbox_id: params[:inbox_id]) if params[:inbox_id].present?
    messages = messages.where(conversations: { display_id: params[:conversation_id] }) if params[:conversation_id].present?
    messages = search_messages(messages) if params[:q].present?
    records = paginated_messages(messages)
    more = records.length > 50
    records = records.first(50)
    render json: { payload: records.map { |message| message_payload(message) }, next_cursor: more ? records.last.id : nil }
  end

  private

  def visible_messages
    inboxes = policy_scope(Current.account.inboxes).where(channel_type: 'Channel::Whatsmeow')
    conversations = Conversations::PermissionFilterService.new(Current.account.conversations, Current.user, Current.account).perform
    Current.account.messages.joins(:conversation).where(private: false, inbox_id: inboxes.select(:id), conversation_id: conversations.select(:id))
           .where("(messages.content_attributes #>> '{}')::jsonb ->> 'whatsmeow_deleted' = 'true'")
  end

  def search_messages(messages)
    term = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q])}%"
    messages.joins(conversation: :contact).where(
      'messages.content ILIKE ? OR contacts.name ILIKE ? OR ' \
      "(messages.content_attributes #>> '{}')::jsonb ->> 'participant_name' ILIKE ?", term, term, term
    )
  end

  def paginated_messages(messages)
    if params[:before].present?
      anchor = messages.find(params[:before])
      messages = messages.where('(messages.created_at, messages.id) < (?, ?)', anchor.created_at, anchor.id)
    end
    messages.includes(:sender, :attachments, conversation: [:inbox, :contact])
            .reorder(created_at: :desc, id: :desc).limit(51).to_a
  end

  def message_payload(message)
    conversation = message.conversation
    {
      id: message.id, message: message.push_event_data,
      conversation_id: conversation.display_id, inbox_id: message.inbox_id, inbox_name: conversation.inbox.name,
      chat_name: conversation.contact.name, sender_name: message.content_attributes['participant_name'].presence || message.sender&.name,
      sender_phone: message.content_attributes['participant_phone'].presence || message.sender.try(:phone_number),
      avatar_url: message.sender.try(:avatar_url)
    }
  end
end
