class MarcosxAi::TranscriptionClient
  MODELS = {
    'openai' => %w[gpt-4o-transcribe gpt-4o-mini-transcribe whisper-1],
    'groq' => %w[whisper-large-v3-turbo whisper-large-v3],
    'gemini' => %w[gemini-2.5-flash gemini-2.5-pro]
  }.freeze

  def self.connection_for(account, provider)
    credential = MarcosxAi::Credential.for_provider(account, provider)
    return unless credential&.enabled && credential.configured?

    { api_key: credential.api_key, api_base: credential.resolved_api_base, source: credential.persisted? ? 'marcosx_ai' : 'integration' }
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
  end

  def transcribe(file)
    client = MarcosxAi::ProviderClient.new(account: @assistant.account, assistant: @assistant,
                                           provider: @provider, model: @settings[:model], purpose: 'transcription')
    text = client.transcribe(file).to_s.strip
    raise CustomExceptions::MarcosxAi, I18n.t('marcosx_ai.errors.empty_response') if text.blank?

    MarcosxAi::Log.create!(account: @assistant.account, assistant: @assistant, event: 'audio_transcribed',
                           response: { provider: client.provider, model: client.model, usage: client.usage })
    text
  rescue Faraday::Error
    raise CustomExceptions::MarcosxAi, I18n.t('marcosx_ai.errors.transcription_failed')
  end
end
