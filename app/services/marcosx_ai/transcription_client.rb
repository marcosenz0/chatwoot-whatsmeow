class MarcosxAi::TranscriptionClient
  MODELS = {
    'openai' => %w[gpt-4o-transcribe gpt-4o-mini-transcribe whisper-1],
    'groq' => %w[whisper-large-v3-turbo whisper-large-v3]
  }.freeze

  def self.connection_for(account, provider)
    credential = account.marcosx_ai_credentials.enabled.find_by(provider: provider)
    if credential&.configured?
      return { api_key: credential.api_key, api_base: credential.resolved_api_base, source: 'marcosx_ai' }
    end

    settings = account.hooks.enabled.find_by(app_id: 'audio_transcription')&.settings || {}
    key = settings["#{provider}_api_key"]
    return unless key.present?

    { api_key: key, api_base: settings["#{provider}_api_base"].presence || MarcosxAi::Credential::PROVIDERS.fetch(provider)[:default_api_base],
      source: 'integration' }
  end

  def self.options_for(account)
    {
      models: MODELS,
      providers: MODELS.keys.map do |provider|
        connection = connection_for(account, provider)
        { provider: provider, configured: connection.present?, source: connection&.dig(:source) }
      end
    }
  end

  def initialize(assistant:)
    @assistant = assistant
    @settings = assistant.resolved_config[:transcription]
    @provider = @settings[:provider]
    @connection = self.class.connection_for(assistant.account, @provider)
  end

  def transcribe(file)
    raise CustomExceptions::MarcosxAi, I18n.t('marcosx_ai.errors.credential_missing') unless @connection

    client = OpenAI::Client.new(access_token: @connection[:api_key], uri_base: @connection[:api_base],
                                request_timeout: MarcosxAi::ProviderClient::TIMEOUT, log_errors: false)
    response = client.audio.transcribe(parameters: { model: @settings[:model], file: file, response_format: 'json' })
    text = response.fetch('text').to_s.strip
    raise CustomExceptions::MarcosxAi, I18n.t('marcosx_ai.errors.empty_response') if text.blank?

    MarcosxAi::Log.create!(account: @assistant.account, assistant: @assistant, event: 'audio_transcribed',
                           response: { provider: @provider, model: @settings[:model], credential_source: @connection[:source],
                                       usage: response['usage'] })
    text
  rescue Faraday::Error
    raise CustomExceptions::MarcosxAi, I18n.t('marcosx_ai.errors.transcription_failed')
  end
end
