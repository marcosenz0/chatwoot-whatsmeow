class Api::V1::Accounts::Conversations::WhatsmeowPixMessagesController < Api::V1::Accounts::Conversations::BaseController
  PIX_FIELDS = %w[key_type key merchant_name].freeze

  before_action :ensure_bot_inbox_access

  def create
    @message = Whatsmeow::PixMessageBuilder.new(
      actor: Current.user || @resource,
      conversation: @conversation,
      attributes: pix_params
    ).perform
    render 'api/v1/accounts/conversations/messages/create'
  rescue CustomExceptions::Whatsmeow::InvalidPixPayload => e
    render json: e.to_hash, status: e.http_status
  end

  private

  def pix_params
    body = request.raw_post.present? ? ActiveSupport::JSON.decode(request.raw_post) : {}
    invalid_pix_params! unless valid_pix_body?(body)

    body
  rescue JSON::ParserError
    invalid_pix_params!
  end

  def valid_pix_body?(body)
    return false unless body.is_a?(Hash)
    return true if body.empty?

    body.keys.sort == PIX_FIELDS.sort && body.values.all?(String)
  end

  def invalid_pix_params!
    raise CustomExceptions::Whatsmeow::InvalidPixPayload.new(
      code: 'invalid_pix_payload',
      message: I18n.t('errors.whatsmeow.pix.invalid_params')
    )
  end

  def ensure_bot_inbox_access
    return unless @resource.is_a?(AgentBot)
    return if @resource.agent_bot_inboxes.active.exists?(account_id: Current.account.id, inbox_id: @conversation.inbox_id)

    raise Pundit::NotAuthorizedError
  end
end
