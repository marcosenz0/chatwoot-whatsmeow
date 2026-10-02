class Api::V1::Accounts::Conversations::WhatsmeowCallSessionsController < Api::V1::Accounts::Conversations::BaseController
  def create
    raise Pundit::NotAuthorizedError unless Current.user
    raise ActionController::BadRequest, 'WhatsApp Direct conversation required' unless @conversation.inbox.channel_type == 'Channel::Whatsmeow'

    target = Whatsmeow::ConversationTargetResolver.new(conversation: @conversation).perform
    raise ActionController::BadRequest, 'A WhatsApp contact or group is required' unless target.match?(/\A[1-9]\d+(?:-\d+)?@(s\.whatsapp\.net|lid|g\.us)\z/)

    expires_at = 90.seconds.from_now
    render json: {
      url: "#{ENV.fetch('WHATSMEOW_CALLS_URL').delete_suffix('/')}/calls/#{@conversation.inbox_id}",
      token: call_token(target, expires_at),
      expires_at: expires_at.iso8601
    }
  end

  private

  def call_token(target, expires_at)
    JWT.encode(
      {
        aud: 'whatsmeow-calls',
        exp: expires_at.to_i,
        inbox_id: @conversation.inbox_id.to_s,
        contact_jid: target,
        conversation_id: @conversation.id,
        agent_id: Current.user.id
      },
      ENV.fetch('WHATSMEOW_SHARED_SECRET'),
      'HS256'
    )
  end
end
