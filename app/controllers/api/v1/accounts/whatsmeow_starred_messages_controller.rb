class Api::V1::Accounts::WhatsmeowStarredMessagesController < Api::V1::Accounts::BaseController
  def index
    stars = WhatsmeowMessageStar.where(inbox_id: accessible_inboxes.select(:id), starred: true)
    stars = stars.where(inbox_id: params[:inbox_id]) if params[:inbox_id].present?
    @pending_count = stars.where(message_id: nil).count
    stars = visible_stars(stars)
    records = stars.includes(message: [:sender, :attachments, { conversation: [:inbox, :contact] }])
                   .order('messages.created_at DESC, whatsmeow_message_stars.id DESC').limit(51).to_a
    more = records.length > 50
    records = records.first(50)
    render json: { payload: records.map { |star| star_payload(star) }, next_cursor: more ? records.last.id : nil, pending_count: @pending_count }
  end

  def sync
    inbox = accessible_inboxes.find(params.require(:inbox_id))
    client = Whatsmeow::SessionClient.new(inbox: inbox)
    status = client.status.fetch('status')
    render json: status == 'connected' ? client.sync_starred_messages : { status: status }
  rescue Whatsmeow::SessionClient::Error => e
    render json: { message: e.message }, status: :bad_gateway
  end

  private

  def accessible_inboxes
    policy_scope(Current.account.inboxes).where(account_id: Current.account.id, channel_type: 'Channel::Whatsmeow')
  end

  def visible_stars(stars)
    conversations = Conversations::PermissionFilterService.new(Current.account.conversations, Current.user, Current.account).perform
    stars = stars.joins(message: :conversation).where(messages: { private: false, conversation_id: conversations.select(:id) })
    stars = stars.where(conversations: { display_id: params[:conversation_id] }) if params[:conversation_id].present?
    stars = search_stars(stars) if params[:q].present?
    return stars if params[:before].blank?

    anchor = stars.find(params[:before])
    stars.where('(messages.created_at, whatsmeow_message_stars.id) < (?, ?)', anchor.message.created_at, anchor.id)
  end

  def search_stars(stars)
    term = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q])}%"
    stars.joins(message: { conversation: :contact }).where(
      "messages.content ILIKE ? OR contacts.name ILIKE ? OR " \
      "(messages.content_attributes #>> '{}')::jsonb ->> 'participant_name' ILIKE ?", term, term, term
    )
  end

  def star_payload(star)
    message = star.message
    conversation = message.conversation
    {
      id: star.id, message: message.push_event_data,
      conversation_id: conversation.display_id, inbox_id: star.inbox_id, inbox_name: conversation.inbox.name,
      chat_name: conversation.contact.name, sender_name: message.content_attributes['participant_name'].presence || message.sender&.name,
      sender_phone: message.content_attributes['participant_phone'].presence || message.sender.try(:phone_number),
      avatar_url: message.sender.try(:avatar_url), starred_at: star.occurred_at.to_i
    }
  end
end
