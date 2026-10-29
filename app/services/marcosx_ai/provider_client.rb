class MarcosxAi::ProviderClient
  TIMEOUT = 120
  MAX_RATE_LIMIT_RETRIES = 2
  MAX_RATE_LIMIT_WAIT = 60
  OUTPUT_LIMITS = { 'groq' => 768, 'openai' => 8000, 'gemini' => 8192 }.freeze
  attr_reader :usage

  def initialize(account:, provider:, model: nil, temperature: 0.7, reasoning_effort: 'medium', assistant: nil, conversation: nil, purpose: 'other',
                 credential: nil, credential_id: nil, routing: true, retry_rate_limits: true, max_output_tokens: nil)
    @account = account
    @assistant = assistant
    @conversation = conversation
    @purpose = purpose
    @provider = provider.to_s
    @credential = credential || MarcosxAi::Credential.for_provider(account, @provider, id: credential_id)
    raise ArgumentError, 'Invalid connection account' if @credential && @credential.account_id != account.id

    @model = model.presence || @credential&.resolved_model
    @temperature = temperature.to_f
    @reasoning_effort = reasoning_effort
    @routing = routing && assistant.present?
    @retry_rate_limits = retry_rate_limits
    @max_output_tokens = max_output_tokens || OUTPUT_LIMITS.fetch(@provider, 8000)
  end

  def chat(messages:, schema: nil, purpose: nil)
    if @routing
      feature = (purpose || @purpose) == 'media_description' ? 'vision' : 'chat'
      return routed(:chat, feature, messages: messages, schema: schema, purpose: purpose)
    end
    rate_limit_retries ||= 0
    ensure_credential!

    case @provider
    when 'openai' then openai_response(messages, schema, purpose || @purpose)
    when 'groq' then compatible_response(messages, schema)
    when 'gemini' then gemini_response(messages, schema)
    end
  rescue Faraday::TooManyRequestsError => e
    delay = Float(e.response&.dig(:headers, 'retry-after').to_s, exception: false)
    if @retry_rate_limits && @provider == 'groq' && delay&.between?(0, MAX_RATE_LIMIT_WAIT) && rate_limit_retries < MAX_RATE_LIMIT_RETRIES
      rate_limit_retries += 1
      Kernel.sleep(delay.ceil)
      retry
    end
    raise_provider_error(e)
  rescue Faraday::Error => e
    raise_provider_error(e)
  end

  def test_connection
    chat(messages: [{ role: 'user', content: 'Reply with OK.' }]).present?
  end

  def models
    ensure_credential!
    if @provider == 'gemini'
      gemini_request(:get, 'models').fetch('models', [])
                                    .select { |item| item.fetch('supportedGenerationMethods', []).include?('generateContent') }
                                    .map { |item| item.fetch('name').delete_prefix('models/') }
    else
      sdk.models.list.fetch('data').pluck('id')
    end
  rescue Faraday::Error => e
    raise_provider_error(e)
  end

  def transcribe(file = nil, audio: nil)
    file ||= audio
    return routed(:transcribe, 'transcription', audio: file) if @routing

    ensure_credential!
    file.rewind
    if @provider == 'gemini'
      return chat(messages: [{ role: 'user', content: [
                    { type: 'input_text', text: 'Transcreva fielmente este áudio no idioma original. Não invente trechos inaudíveis.' },
                    { type: 'input_file', file_data: "data:audio/mpeg;base64,#{Base64.strict_encode64(file.read)}" }
                  ] }])
    end
    model = MarcosxAi::TranscriptionClient::MODELS.fetch(@provider).include?(@model) ? @model :
      MarcosxAi::TranscriptionClient::MODELS.fetch(@provider).first
    response = sdk.audio.transcribe(parameters: { model: model, file: file, response_format: 'json' })
    @usage = response['usage']
    response['text'].to_s.presence || raise_empty_response
  rescue Faraday::Error => e
    raise_provider_error(e)
  end

  def provider
    @actual_provider || @provider
  end

  def model
    @actual_model || @model
  end

  private

  def routed(task, feature, **arguments)
    router = MarcosxAi::ConnectionRouter.new(assistant: @assistant, feature: feature, conversation: @conversation,
                                             temperature: @temperature, reasoning_effort: @reasoning_effort, purpose: @purpose)
    result = router.perform(task, **arguments)
    @usage = router.client.usage
    @actual_provider = router.client.provider
    @actual_model = router.client.model
    result
  end

  def ensure_credential!
    return if @credential&.enabled && @credential.configured?

    raise CustomExceptions::MarcosxAi.new(I18n.t('marcosx_ai.errors.credential_missing'), provider_failure: true)
  end

  def sdk
    @sdk ||= OpenAI::Client.new(access_token: @credential.api_key, uri_base: @credential.resolved_api_base,
                                request_timeout: TIMEOUT, log_errors: false)
  end

  def openai_response(messages, schema, purpose)
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    parameters = { model: @model, store: false, max_output_tokens: @max_output_tokens }.merge(
      MarcosxAi::PromptCache.parameters(messages, account_id: @account.id, model: @model, api_base: @credential.resolved_api_base)
    )
    if reasoning_model?
      parameters[:reasoning] = { effort: @reasoning_effort }
    else
      parameters[:temperature] = @temperature
    end
    parameters[:text] = { format: { type: 'json_schema', name: 'customer_reply', strict: true, schema: schema } } if schema
    response = sdk.json_post(path: '/responses', parameters: parameters)
    @usage = response['usage']
    MarcosxAi::ProviderUsage.record(account: @account, assistant: @assistant, conversation: @conversation, model: @model,
                                    purpose: purpose, response: response, parameters: parameters, started_at: started_at)
    raise_output_limit if response.dig('incomplete_details', 'reason') == 'max_output_tokens'
    content = response.fetch('output', []).flat_map { |item| item.fetch('content', []) }
    text = content.select { |item| item['type'] == 'output_text' }.pluck('text').join
    raise_empty_response if text.blank?

    text
  end

  def reasoning_model?
    @model.start_with?('gpt-5', 'gpt-6', 'o3', 'o4')
  end

  def compatible_response(messages, schema)
    parameters = { model: @model, messages: compatible_messages(messages), temperature: @temperature, max_tokens: @max_output_tokens }
    parameters[:reasoning_effort] = @reasoning_effort if MarcosxAi::ModelCatalog.describe(@model, @provider)[:reasoning]
    if schema
      parameters[:response_format] = if MarcosxAi::ModelCatalog.describe(@model, @provider)[:structured_outputs]
                                       { type: 'json_schema', json_schema: { name: 'customer_reply', strict: true, schema: schema } }
                                     else
                                       { type: 'json_object' }
                                     end
    end
    response = sdk.chat(parameters: parameters)
    raise_output_limit if response.dig('choices', 0, 'finish_reason') == 'length'
    @usage = response['usage']
    response.dig('choices', 0, 'message', 'content').to_s.presence ||
      raise_empty_response
  end

  def compatible_messages(messages)
    messages.map do |message|
      content = message[:content]
      content = content.map { |part| compatible_part(part) } if content.is_a?(Array)
      { role: message[:role] == 'developer' ? 'system' : message[:role], content: content }
    end
  end

  def compatible_part(part)
    return { type: 'image_url', image_url: { url: part[:image_url] } } if part[:type] == 'input_image'
    return { type: 'text', text: part[:text] } if part[:type] == 'input_text'

    raise CustomExceptions::MarcosxAi, I18n.t('marcosx_ai.errors.unsupported_media')
  end

  def gemini_response(messages, schema)
    instructions, history = messages.partition { |item| %w[system developer].include?(item[:role]) }
    body = {
      systemInstruction: { parts: instructions.map { |item| { text: item[:content] } } },
      contents: history.map do |item|
        {
          role: item[:role] == 'assistant' ? 'model' : 'user',
          parts: item[:content].is_a?(Array) ? item[:content].map { |part| gemini_part(part) } : [{ text: item[:content] }]
        }
      end,
      generationConfig: { temperature: @temperature, maxOutputTokens: @max_output_tokens }
    }
    body[:generationConfig].merge!(responseMimeType: 'application/json', responseJsonSchema: schema) if schema
    response = gemini_request(:post, "models/#{@model}:generateContent", body)
    raise_output_limit if response.dig('candidates', 0, 'finishReason') == 'MAX_TOKENS'
    @usage = response['usageMetadata']
    response.dig('candidates', 0, 'content', 'parts')&.reject { |part| part['thought'] }&.pluck('text')&.join.presence ||
      raise_empty_response
  end

  def gemini_part(part)
    return { text: part[:text] } if part[:type] == 'input_text'

    data_url = part[:image_url] || part[:file_data]
    mime_type, data = data_url.split(';base64,', 2)
    { inlineData: { mimeType: mime_type.delete_prefix('data:'), data: data } }
  end

  def gemini_request(method, path, body = nil)
    connection = Faraday.new(url: "#{@credential.resolved_api_base.chomp('/')}/") do |builder|
      builder.request :json
      builder.response :json
      builder.response :raise_error
      builder.options.timeout = TIMEOUT
      builder.options.open_timeout = 10
    end
    connection.run_request(method, path, body, { 'x-goog-api-key' => @credential.api_key }).body
  end

  def raise_provider_error(error)
    status = error.response&.dig(:status)
    message = error.response&.dig(:body, 'error', 'message') if error.response&.dig(:body).is_a?(Hash)
    message = message.to_s.gsub(@credential.api_key.to_s, '[redacted]').gsub(/(?:sk-|gsk_)[\w-]+/, '[redacted]')
    detail = I18n.t('marcosx_ai.errors.provider', provider: @credential.display_name, status: status || 'timeout', detail: message.truncate(300))
    delay = Float(error.response&.dig(:headers, 'retry-after').to_s, exception: false)
    raise CustomExceptions::MarcosxAi.new(detail, provider_failure: true, provider_status: status, retry_after: delay)
  end

  def raise_empty_response
    raise CustomExceptions::MarcosxAi.new(I18n.t('marcosx_ai.errors.empty_response'), provider_failure: true)
  end

  def raise_output_limit
    raise CustomExceptions::MarcosxAi.new(I18n.t('marcosx_ai.errors.output_limit'), provider_failure: true)
  end
end
