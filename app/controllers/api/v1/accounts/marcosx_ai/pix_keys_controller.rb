class Api::V1::Accounts::MarcosxAi::PixKeysController < Api::V1::Accounts::MarcosxAi::BaseController
  before_action :ensure_admin!
  before_action :set_assistant

  def index
    render_keys
  end

  def create
    @item = @assistant.pix_keys.new(account: Current.account)
    @item.configure!(key_params)
    render_keys(:created)
  rescue ActiveRecord::RecordInvalid, ArgumentError => e
    render_invalid(e)
  end

  def update
    @item = @assistant.pix_keys.find(params[:id])
    @item.configure!(key_params)
    render_keys
  rescue ActiveRecord::RecordInvalid, ArgumentError => e
    render_invalid(e)
  end

  def destroy
    @assistant.with_lock do
      @assistant.pix_keys.find(params[:id]).destroy!
      @assistant.pix_keys.find_by(position: 2)&.update!(position: 1) unless @assistant.pix_keys.exists?(position: 1)
    end
    render_keys
  end

  private

  def set_assistant
    @assistant = Current.account.marcosx_ai_assistants.find(params[:assistant_id])
  end

  def key_params
    data = params.require(:pix_key).permit(:title, :description, :key_type, :key, :merchant_name, :enabled, :primary).to_h
    data.each do |field, value|
      raise ArgumentError unless %w[enabled primary].include?(field) ? [true, false].include?(value) : value.is_a?(String)
    end
    data
  end

  def render_keys(status = :ok)
    render json: { pix_keys: @assistant.pix_keys.ordered.map(&:public_data), active_limit: 2 }, status: status
  end

  def render_invalid(error)
    message = error.is_a?(ArgumentError) && error.message == I18n.t('marcosx_ai.errors.pix_active_limit') ? error.message :
      I18n.t('marcosx_ai.errors.invalid_pix_key')
    render json: { error: message }, status: :unprocessable_entity
  end
end
