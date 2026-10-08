class Api::V1::Accounts::Inboxes::WhatsmeowProfilesController < Api::V1::Accounts::BaseController
  before_action :fetch_inbox
  rescue_from Whatsmeow::SessionClient::Error, with: :render_service_error

  def show
    render json: client.own_profile
  end

  def update
    render json: client.update_profile(profile_params)
  end

  def photo
    render json: client.own_profile_photo
  end

  def update_photo
    render json: client.update_profile_photo(params.require(:photo))
  end

  def destroy_photo
    render json: client.remove_profile_photo
  end

  private

  def fetch_inbox
    @inbox = Current.account.inboxes.find(params[:inbox_id])
    authorize @inbox, action_name == 'photo' ? :show? : :update?
    raise ActiveRecord::RecordNotFound unless @inbox.channel_type == 'Channel::Whatsmeow'
  end

  def client
    @client ||= Whatsmeow::SessionClient.new(inbox: @inbox)
  end

  def profile_params
    params.permit(
      :name, :about, :about_duration,
      business: [:address, :email, :description, { websites: [], hours: [:timezone, { days: [:day, :mode, :open, :close] }] }]
    ).to_h
  end

  def render_service_error(error)
    render json: { message: error.message }, status: :unprocessable_entity
  end
end
