class Messages::AudioTranscriptionService
  TRANSCRIPTION_BYTE_LIMIT = 25_000_000
  INTEGRATION_APP_ID = 'audio_transcription'.freeze
  LEGACY_OPENAI_API_KEY_CONFIG = 'CAPTAIN_OPEN_AI_API_KEY'.freeze
  LEGACY_OPENAI_MODEL_CONFIG = 'CAPTAIN_OPEN_AI_MODEL'.freeze
  LEGACY_OPENAI_ENDPOINT_CONFIG = 'CAPTAIN_OPEN_AI_ENDPOINT'.freeze
  PROVIDERS = %w[openai groq].freeze
  LEGACY_OPENAI_TRANSCRIPTION_MODEL = 'whisper-1'.freeze
  DEFAULT_TRANSCRIPTION_MODELS = {
    'openai' => 'gpt-4o-mini-transcribe',
    'groq' => 'whisper-large-v3-turbo'
  }.freeze
  DEFAULT_SUMMARY_MODELS = {
    'openai' => 'gpt-4.1-mini',
    'groq' => 'llama-3.3-70b-versatile'
  }.freeze
  DEFAULT_API_BASES = {
    'openai' => 'https://api.openai.com/v1',
    'groq' => 'https://api.groq.com/openai/v1'
  }.freeze

  attr_reader :attachment, :message, :account, :operation

  def initialize(attachment, operation: :transcribe)
    @attachment = attachment
    @message = attachment&.message
    @account = message&.account
    @operation = operation.to_sym
  end

  def perform
    return { error: 'Audio attachment not found' } if attachment.blank?
    return { error: 'Message not found' } if message.blank?
    return { error: transcription_unavailable_error } unless can_transcribe?
    return { error: 'Audio too large for Whisper' } if audio_too_large?

    operation == :summarize ? summarize : transcribe
  rescue Faraday::Error, JSON::ParserError, KeyError, ActiveStorage::FileNotFoundError => e
    Rails.logger.warn("[audio-transcription] #{e.class}: #{e.message}")
    { error: 'Could not process audio. Check the transcription integration settings and try again.' }
  end

  private

  def can_transcribe?
    return provider_order.any? { |provider| api_key_for(provider).present? } if audio_transcription_hook.present?

    legacy_audio_transcription_available?
  end

  def transcription_unavailable_error
    return 'Audio transcription integration is not configured' if audio_transcription_hook.present?

    'Transcription limit exceeded'
  end

  def transcribe
    transcriptions = transcribe_audio
    { success: true, transcriptions: transcriptions }
  end

  def summarize
    summary = summarize_audio
    { success: true, summary: summary }
  end

  def audio_too_large?
    blob = attachment.file&.blob
    return false unless blob

    blob.byte_size > TRANSCRIPTION_BYTE_LIMIT
  end

  def audio_transcription_hook
    @audio_transcription_hook ||= account&.hooks&.enabled&.find_by(app_id: INTEGRATION_APP_ID)
  end

  def settings
    @settings ||= (audio_transcription_hook&.settings || {}).with_indifferent_access
  end

  def provider_order
    return ['openai'] if audio_transcription_hook.blank?

    primary = settings[:provider].presence || 'openai'
    fallback = settings[:fallback_provider].presence
    fallback = nil if fallback == 'none' || fallback == primary

    [primary, fallback].compact.select { |provider| PROVIDERS.include?(provider) }
  end

  def api_key_for(provider)
    settings[:"#{provider}_api_key"].presence || legacy_openai_api_key(provider)
  end

  def api_base_for(provider)
    return legacy_openai_api_base if audio_transcription_hook.blank? && provider == 'openai'

    settings[:"#{provider}_api_base"].presence || DEFAULT_API_BASES.fetch(provider)
  end

  def transcription_model_for(provider)
    return LEGACY_OPENAI_TRANSCRIPTION_MODEL if audio_transcription_hook.blank? && provider == 'openai'

    settings[:"#{provider}_transcription_model"].presence || DEFAULT_TRANSCRIPTION_MODELS.fetch(provider)
  end

  def summary_model_for(provider)
    return legacy_openai_model if audio_transcription_hook.blank? && provider == 'openai'

    settings[:"#{provider}_summary_model"].presence || DEFAULT_SUMMARY_MODELS.fetch(provider)
  end

  def legacy_audio_transcription_available?
    account&.feature_enabled?('captain_integration') &&
      ActiveModel::Type::Boolean.new.cast(account&.audio_transcriptions) &&
      account.usage_limits[:captain][:responses][:current_available].positive? &&
      legacy_openai_api_key('openai').present?
  end

  def legacy_openai_api_key(provider)
    return if provider != 'openai'

    @legacy_openai_api_key ||= InstallationConfig.find_by(name: LEGACY_OPENAI_API_KEY_CONFIG)&.value
  end

  def legacy_openai_model
    InstallationConfig.find_by(name: LEGACY_OPENAI_MODEL_CONFIG)&.value.presence || DEFAULT_SUMMARY_MODELS.fetch('openai')
  end

  def legacy_openai_api_base
    endpoint = InstallationConfig.find_by(name: LEGACY_OPENAI_ENDPOINT_CONFIG)&.value
    return DEFAULT_API_BASES.fetch('openai') if endpoint.blank?

    normalized_endpoint = endpoint.chomp('/')
    return normalized_endpoint if normalized_endpoint.end_with?('/v1')

    "#{normalized_endpoint}/v1"
  end

  def language
    configured_language = settings[:language].to_s.strip
    return if configured_language.blank? || configured_language == 'auto'

    configured_language
  end

  def fetch_audio_file
    blob = attachment.file.blob
    temp_dir = Rails.root.join('tmp/uploads/audio-transcriptions')
    FileUtils.mkdir_p(temp_dir)
    temp_file_name = "#{blob.key}-#{blob.filename}"

    if blob.filename.extension_without_delimiter.blank?
      extension = extension_from_content_type(blob.content_type)
      temp_file_name = "#{temp_file_name}.#{extension}" if extension.present?
    end

    temp_file_path = File.join(temp_dir, temp_file_name)

    File.open(temp_file_path, 'wb') do |file|
      blob.open do |blob_file|
        IO.copy_stream(blob_file, file)
      end
    end

    temp_file_path
  end

  def transcribe_audio
    transcribed_text = attachment.meta&.[]('transcribed_text').to_s
    return transcribed_text if transcribed_text.present?

    temp_file_path = fetch_audio_file
    provider, transcribed_text = first_successful_provider { |candidate| transcribe_with_provider(candidate, temp_file_path) }
    update_audio_meta('transcribed_text', transcribed_text, provider)
    transcribed_text
  ensure
    FileUtils.rm_f(temp_file_path) if temp_file_path.present?
  end

  def summarize_audio
    summary_text = attachment.meta&.[]('summary_text').to_s
    return summary_text if summary_text.present?

    transcribed_text = transcribe_audio
    return '' if transcribed_text.blank?

    provider, summary_text = first_successful_provider { |candidate| summarize_with_provider(candidate, transcribed_text) }
    update_audio_meta('summary_text', summary_text, provider)
    summary_text
  end

  def first_successful_provider
    last_error = nil

    provider_order.each_with_index do |provider, index|
      next if api_key_for(provider).blank?

      return [provider, yield(provider)]
    rescue Faraday::Error, JSON::ParserError, KeyError => e
      last_error = e
      Rails.logger.warn("[audio-transcription] #{provider} failed: #{e.class}: #{e.message}")
      raise if index == provider_order.length - 1
    end

    raise last_error if last_error

    raise KeyError, 'No configured transcription provider was available'
  end

  def transcribe_with_provider(provider, file_path)
    response = connection_for(provider).post('audio/transcriptions') do |request|
      request.headers['Authorization'] = "Bearer #{api_key_for(provider)}"
      request.body = transcription_payload(provider, file_path)
    end

    JSON.parse(response.body).fetch('text').to_s.strip
  end

  def summarize_with_provider(provider, transcribed_text)
    response = connection_for(provider).post('chat/completions') do |request|
      request.headers['Authorization'] = "Bearer #{api_key_for(provider)}"
      request.headers['Content-Type'] = 'application/json'
      request.body = {
        model: summary_model_for(provider),
        temperature: 0.2,
        messages: summary_messages(transcribed_text)
      }.to_json
    end

    JSON.parse(response.body).dig('choices', 0, 'message', 'content').to_s.strip
  end

  def connection_for(provider)
    Faraday.new(url: api_base_for(provider)) do |connection|
      connection.request :multipart
      connection.request :url_encoded
      connection.response :raise_error
      connection.options.timeout = 90
      connection.options.open_timeout = 10
    end
  end

  def transcription_payload(provider, file_path)
    blob = attachment.file.blob
    payload = {
      model: transcription_model_for(provider),
      file: Faraday::Multipart::FilePart.new(
        file_path,
        blob.content_type.presence || 'application/octet-stream',
        blob.filename.to_s
      ),
      response_format: 'json',
      temperature: 0.0
    }
    payload[:language] = language if language.present?
    payload[:chunking_strategy] = 'auto' if transcription_model_for(provider) == 'gpt-4o-transcribe-diarize'
    payload
  end

  def summary_messages(transcribed_text)
    [
      {
        role: 'system',
        content: 'Resuma audios de atendimento em portugues claro, curto e util para um agente de suporte. Destaque intencao, pedidos, dados importantes e proximos passos quando existirem.'
      },
      {
        role: 'user',
        content: "Transcricao do audio:\n\n#{transcribed_text}"
      }
    ]
  end

  def update_audio_meta(key, value, provider)
    return if value.blank?

    metadata = (attachment.meta || {}).merge(
      key => value,
      "#{key}_provider" => provider,
      "#{key}_generated_at" => Time.current.iso8601
    )
    attachment.update!(meta: metadata)
    message.reload.send_update_event
    message.account.increment_response_usage if audio_transcription_hook.blank? && key == 'transcribed_text'

    return unless ChatwootApp.advanced_search_allowed?

    message.reindex
  end

  def extension_from_content_type(content_type)
    subtype = content_type.to_s.downcase.split(';').first.to_s.split('/').last.to_s
    return if subtype.blank?

    {
      'x-m4a' => 'm4a',
      'x-wav' => 'wav',
      'x-mp3' => 'mp3'
    }.fetch(subtype, subtype)
  end
end
