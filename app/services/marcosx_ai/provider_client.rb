class MarcosxAi::ProviderClient
  TIMEOUT = 120
  attr_reader :usage

  def initialize(account:, provider:, model: nil, temperature: 0.7, reasoning_effort: 'medium')
    @provider = provider.to_s
    @credential = account.marcosx_ai_credentials.find_by!(provider: @provider)
    @model = model.presence || @credential.resolved_model
    @temperature = temperature.to_f
    @reasoning_effort = reasoning_effort
  end

  def chat(messages:, schema: nil)
    raise CustomExceptions::MarcosxAi, I18n.t('marcosx_ai.errors.credential_missing') unless @credential.enabled && @credential.configured?

    case @provider
    when 'openai' then openai_response(messages, schema)
    when 'groq' then compatible_response(messages, schema)
    when 'gemini' then gemini_response(messages, schema)
    end
  rescue Faraday::Error => e
    raise_provider_error(e)
  end

  def test_connection
    chat(messages: [{ role: 'user', content: 'Reply with OK.' }]).present?
  end

  def models
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

  def transcribe(file)
    model = @provider == 'groq' ? 'whisper-large-v3-turbo' : 'gpt-4o-transcribe'
    sdk.audio.transcribe(parameters: { model: model, file: file, response_format: 'json' }).fetch('text')
  rescue Faraday::Error => e
    raise_provider_error(e)
  end

  private

  def sdk
    @sdk ||= OpenAI::Client.new(access_token: @credential.api_key, uri_base: @credential.resolved_api_base,
                                request_timeout: TIMEOUT, log_errors: false)
  end

  def openai_response(messages, schema)
    parameters = { model: @model, input: messages, store: false, max_output_tokens: 8000 }
    if reasoning_model?
      parameters[:reasoning] = { effort: @reasoning_effort }
    else
      parameters[:temperature] = @temperature
    end
    parameters[:text] = { format: { type: 'json_schema', name: 'customer_reply', strict: true, schema: schema } } if schema
    response = sdk.json_post(path: '/responses', parameters: parameters)
    @usage = response['usage']
    content = response.fetch('output', []).flat_map { |item| item.fetch('content', []) }
    text = content.select { |item| item['type'] == 'output_text' }.pluck('text').join
    raise CustomExceptions::MarcosxAi, I18n.t('marcosx_ai.errors.empty_response') if text.blank?

    text
  end

  def reasoning_model?
    @model.start_with?('gpt-5', 'gpt-6', 'o3', 'o4')
  end

  def compatible_response(messages, schema)
    parameters = { model: @model, messages: compatible_messages(messages), temperature: @temperature, max_tokens: 4096 }
    parameters[:response_format] = { type: 'json_object' } if schema
    response = sdk.chat(parameters: parameters)
    @usage = response['usage']
    response.dig('choices', 0, 'message', 'content').to_s.presence ||
      raise(CustomExceptions::MarcosxAi, I18n.t('marcosx_ai.errors.empty_response'))
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
      generationConfig: { temperature: @temperature, maxOutputTokens: 8192 }
    }
    body[:generationConfig].merge!(responseMimeType: 'application/json', responseJsonSchema: schema) if schema
    response = gemini_request(:post, "models/#{@model}:generateContent", body)
    @usage = response['usageMetadata']
    response.dig('candidates', 0, 'content', 'parts')&.reject { |part| part['thought'] }&.pluck('text')&.join.presence ||
      raise(CustomExceptions::MarcosxAi, I18n.t('marcosx_ai.errors.empty_response'))
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
    message = message.to_s.gsub(@credential.api_key.to_s, '[redacted]').gsub(/sk-[\w-]+/, '[redacted]')
    raise CustomExceptions::MarcosxAi, I18n.t('marcosx_ai.errors.provider', provider: @credential.display_name,
                                                                            status: status || 'timeout', detail: message.truncate(300))
  end
end
