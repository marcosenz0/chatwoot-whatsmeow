class Api::V1::Accounts::Inboxes::WhatsmeowPixController < Api::V1::Accounts::BaseController
  before_action :fetch_inbox
  before_action :ensure_whatsmeow_inbox

  def show
    render json: response_payload
  end

  def update
    authorize @inbox, :update?
    pix = Whatsmeow::PixPayload.new(pix_params).validate!
    @inbox.channel.update!(
      pix_key_type: pix.key_type,
      pix_key: pix.key,
      pix_merchant_name: pix.merchant_name
    )
    render json: response_payload
  rescue CustomExceptions::Whatsmeow::InvalidPixPayload => e
    render_pix_error(e)
  end

  def destroy
    authorize @inbox, :update?
    @inbox.channel.update!(pix_key_type: nil, pix_key: nil, pix_merchant_name: nil)
    render json: response_payload
  end

  private

  def fetch_inbox
    @inbox = Current.account.inboxes.find(params[:inbox_id])
    if @resource.is_a?(AgentBot) && !@resource.agent_bot_inboxes.active.exists?(account_id: Current.account.id, inbox_id: @inbox.id)
      raise Pundit::NotAuthorizedError
    end

    return unless action_name == 'show'

    if Current.account_user&.administrator?
      authorize @inbox, :update?
    elsif params[:conversation_id].present?
      conversation = Current.account.conversations.find_by!(display_id: params[:conversation_id], inbox_id: @inbox.id)
      authorize conversation, :show?
    else
      authorize @inbox, :show?
    end
  end

  def ensure_whatsmeow_inbox
    return if @inbox.channel_type == 'Channel::Whatsmeow'

    raise CustomExceptions::Whatsmeow::InvalidPixPayload.new(
      code: 'unsupported_channel',
      message: I18n.t('errors.whatsmeow.pix.unsupported_channel')
    )
  rescue CustomExceptions::Whatsmeow::InvalidPixPayload => e
    render_pix_error(e)
  end

  def pix_params
    params.permit(:key_type, :key, :merchant_name)
  end

  def response_payload
    channel = @inbox.channel
    pix = Whatsmeow::PixPayload.from_channel(channel)

    {
      configured: channel.pix_configured?,
      can_manage: Current.account_user&.administrator? || false,
      pix: channel.pix_configured? ? pix.to_h : nil
    }
  end

  def render_pix_error(error)
    render json: error.to_hash, status: error.http_status
  end
end
