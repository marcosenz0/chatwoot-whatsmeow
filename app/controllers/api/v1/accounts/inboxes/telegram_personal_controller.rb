class Api::V1::Accounts::Inboxes::TelegramPersonalController < Api::V1::Accounts::BaseController
  before_action :fetch_inbox
  rescue_from TelegramPersonal::SessionClient::Error, with: :render_service_error

  def show
    render_session(client.status)
  end

  def create
    render_session(client.connect)
  end

  def password
    render_session(client.password(params.require(:password)))
  end

  def destroy
    render_session(client.disconnect)
  end

  private

  def fetch_inbox
    @inbox = Current.account.inboxes.find(params[:inbox_id])
    authorize @inbox, :update?
    head :not_found unless @inbox.channel_type == 'Channel::TelegramPersonal'
  end

  def client = TelegramPersonal::SessionClient.new(inbox: @inbox)

  def render_session(payload)
    @inbox.channel.assign_attributes(payload.slice('status', 'telegram_user_id', 'username'))
    @inbox.channel.save! if @inbox.channel.changed?
    response.headers['Cache-Control'] = 'no-store'
    render json: payload
  end

  def render_service_error(error)
    render json: { error: error.code }, status: :unprocessable_entity
  end
end
