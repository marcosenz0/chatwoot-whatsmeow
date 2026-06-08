class Api::V1::Accounts::MarcosxAi::CredentialsController < Api::V1::Accounts::MarcosxAi::BaseController
  before_action :ensure_admin!
  before_action :set_credential, only: [:show, :update, :destroy]

  def index
    render json: { credentials: Current.account.marcosx_ai_credentials.order(:provider).map(&:redacted) }
  end

  def show
    render json: { credential: @credential.redacted }
  end

  def create
    credential = Current.account.marcosx_ai_credentials.find_or_initialize_by(provider: credential_params[:provider])
    attrs = credential_params.except(:provider)
    attrs.delete(:api_key) if attrs[:api_key].blank?
    attrs.delete_if { |_, value| value.blank? && value != false }
    credential.assign_attributes(attrs)
    credential.enabled = true unless credential_params.key?(:enabled)
    credential.save!

    render json: { credential: credential.redacted }
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def update
    attrs = credential_params.except(:provider)
    attrs.delete(:api_key) if attrs[:api_key].blank?
    @credential.update!(attrs)

    render json: { credential: @credential.redacted }
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def destroy
    @credential.destroy!
    head :no_content
  end

  def test
    provider = params[:provider].presence || params.dig(:credential, :provider)
    credential = Current.account.marcosx_ai_credentials.find_by!(provider: provider)
    ok = MarcosxAi::ProviderClient.new(
      account: Current.account,
      provider: credential.provider,
      model: credential.resolved_model
    ).test_connection

    render json: { success: ok }
  rescue StandardError => e
    render json: { success: false, error: e.message }, status: :unprocessable_entity
  end

  private

  def set_credential
    @credential = Current.account.marcosx_ai_credentials.find(params[:id])
  end

  def credential_params
    params.require(:credential).permit(:provider, :api_key, :api_base, :model, :enabled)
  end
end
