class Api::V1::Accounts::MarcosxAi::CredentialsController < Api::V1::Accounts::MarcosxAi::BaseController
  before_action :ensure_admin!
  before_action :set_credential, only: [:show, :update, :destroy]

  def index
    render json: { credentials: MarcosxAi::Credential.connections_for(Current.account) }
  end

  def show
    render json: { credential: @credential.redacted }
  end

  def health
    render json: { credentials: MarcosxAi::Credential.connections_for(Current.account),
                   assistants: Current.account.marcosx_ai_assistants.map { |assistant|
                     { id: assistant.id, connection_status: assistant.connection_status }
                   } }
  end

  def create
    credential = if credential_params[:name].present?
                   Current.account.marcosx_ai_credentials.new(provider: credential_params[:provider])
                 else
                   Current.account.marcosx_ai_credentials.where(provider: credential_params[:provider]).order(:id).first ||
                     Current.account.marcosx_ai_credentials.new(provider: credential_params[:provider])
                 end
    attrs = credential_params.except(:provider)
    attrs.delete(:api_key) if attrs[:api_key].blank?
    if !credential.configured? && attrs[:api_key].blank? &&
       (attrs[:name].blank? || (attrs[:name] == 'Principal' && !Current.account.marcosx_ai_credentials.exists?(provider: credential.provider)))
      attrs[:api_key] = MarcosxAi::Credential.for_provider(Current.account, credential.provider)&.api_key
    end
    raise ArgumentError, I18n.t('marcosx_ai.errors.credential_missing') if credential.new_record? && attrs[:api_key].blank?

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
    attrs[:health] = {} if attrs[:api_key].present? || (attrs.key?(:api_base) && attrs[:api_base] != @credential.api_base)
    @credential.update!(attrs)

    render json: { credential: @credential.redacted }
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def destroy
    referenced = Current.account.marcosx_ai_assistants.any? do |assistant|
      config = assistant.resolved_config
      [config, config[:vision], config[:transcription]].any? do |settings|
        settings[:connection_id] == @credential.id || settings.dig(:fallback, :connection_id) == @credential.id
      end
    end
    return render json: { error: I18n.t('marcosx_ai.errors.connection_in_use') }, status: :unprocessable_entity if referenced

    @credential.destroy!
    head :no_content
  end

  def test
    provider = params[:provider].presence || params.dig(:credential, :provider)
    credential = MarcosxAi::Credential.for_provider(Current.account, provider, id: params[:credential_id].presence)
    raise ActiveRecord::RecordNotFound unless credential

    client = MarcosxAi::ProviderClient.new(
      account: Current.account,
      provider: credential.provider,
      model: params[:model].presence || credential.resolved_model,
      credential: credential
    )
    selected_model = params[:model].presence || credential.resolved_model
    ok = if MarcosxAi::TranscriptionClient::MODELS.fetch(provider, []).include?(selected_model)
           client.models.include?(selected_model)
         else
           client.test_connection
         end
    raise CustomExceptions::MarcosxAi.new(I18n.t('marcosx_ai.errors.invalid_connection'), provider_failure: true) unless ok

    credential.record_health!

    render json: { success: ok }
  rescue StandardError => e
    credential&.record_health!(error: e) if e.is_a?(CustomExceptions::MarcosxAi) && e.provider_failure
    render json: { success: false, error: e.message }, status: :unprocessable_entity
  end

  def models
    provider = params[:provider]
    return render json: { error: 'Invalid provider' }, status: :unprocessable_entity unless MarcosxAi::Credential::PROVIDERS.key?(provider)

    render json: MarcosxAi::ModelCatalog.for_provider(account: Current.account, provider: provider, credential_id: params[:credential_id].presence,
                                                      refresh: params[:refresh] == 'true')
  rescue CustomExceptions::MarcosxAi => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def set_credential
    @credential = Current.account.marcosx_ai_credentials.find(params[:id])
  end

  def credential_params
    params.require(:credential).permit(:provider, :name, :api_key, :api_base, :model, :enabled)
  end
end
