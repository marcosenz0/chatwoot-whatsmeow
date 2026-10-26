class Api::V1::Accounts::MarcosxAi::VoicesController < Api::V1::Accounts::MarcosxAi::BaseController
  before_action :ensure_admin!
  before_action :set_assistant

  def show
    render json: { credentials: @assistant.voice_credentials.map(&:redacted), models: MarcosxAi::VoiceClient::MODELS,
                   encryption_ready: Chatwoot.encryption_configured?,
                   transcription: MarcosxAi::TranscriptionClient.options_for(Current.account) }
  end

  def update
    provider = params[:provider]
    key = params[:api_key]
    unless MarcosxAi::VoiceCredential::PROVIDERS.include?(provider) && key.is_a?(String) && key.strip.present? && key.length <= 4096
      return render json: { error: 'Invalid voice credential' }, status: :unprocessable_entity
    end

    credential = @assistant.voice_credentials.find_or_initialize_by(provider: provider)
    credential.update!(account: Current.account, api_key: key.strip)
    render json: { credential: credential.redacted }
  rescue ActiveRecord::RecordInvalid
    render json: { error: 'Voice credentials require encrypted server storage' }, status: :unprocessable_entity
  end

  def destroy
    @assistant.voice_credentials.find_by!(provider: params[:provider]).destroy!
    head :no_content
  end

  def preview
    audio = MarcosxAi::VoiceClient.new(assistant: @assistant).synthesize(params[:text])
    send_data audio, type: 'audio/mpeg', disposition: 'inline', filename: 'voice-preview.mp3'
  rescue MarcosxAi::VoiceClient::Error, CustomExceptions::MarcosxAi
    render json: { error: 'Unable to generate voice preview. Check the saved settings, credential, balance and spoken text.' },
           status: :unprocessable_entity
  end

  private

  def set_assistant
    @assistant = Current.account.marcosx_ai_assistants.find(params[:assistant_id])
  end
end
