require 'net/http'
require 'cgi'

class MarcosxAi::ProviderClient
  DEFAULT_TIMEOUT = 45

  def initialize(account:, provider:, model: nil, temperature: 0.7)
    @account = account
    @provider = provider.to_s
    @model = model
    @temperature = temperature.to_f
    @credential = account.marcosx_ai_credentials.enabled.find_by(provider: @provider)
  end

  def chat(messages:)
    raise 'Credencial de IA nao configurada para este provedor.' unless credential_ready?

    @provider == 'gemini' ? gemini_chat(messages) : openai_compatible_chat(messages)
  end

  def test_connection
    chat(messages: [{ role: 'user', content: 'Responda apenas OK.' }]).present?
  end

  private

  def credential_ready?
    @credential&.api_key.present?
  end

  def resolved_model
    @model.presence || @credential.resolved_model
  end

  def resolved_api_base
    @credential.resolved_api_base.chomp('/')
  end

  def openai_compatible_chat(messages)
    uri = URI("#{resolved_api_base}/chat/completions")
    response = execute_json_request(
      uri,
      {
        model: resolved_model,
        messages: messages,
        temperature: @temperature
      },
      'Authorization' => "Bearer #{@credential.api_key}"
    )

    response.dig('choices', 0, 'message', 'content').to_s.strip
  end

  def gemini_chat(messages)
    uri = URI(
      "#{resolved_api_base}/models/#{resolved_model}:generateContent?key=#{CGI.escape(@credential.api_key)}"
    )
    response = execute_json_request(
      uri,
      {
        contents: gemini_contents(messages),
        generationConfig: {
          temperature: @temperature
        }
      }
    )

    response.dig('candidates', 0, 'content', 'parts', 0, 'text').to_s.strip
  end

  def gemini_contents(messages)
    system_messages, conversation_messages = messages.partition { |message| message[:role].to_s == 'system' }
    system_prompt = system_messages.pluck(:content).join("\n\n")

    conversation_messages.map.with_index do |message, index|
      content = message[:content].to_s
      content = "#{system_prompt}\n\n#{content}" if index.zero? && system_prompt.present?

      {
        role: message[:role].to_s == 'assistant' ? 'model' : 'user',
        parts: [{ text: content }]
      }
    end
  end

  def execute_json_request(uri, body, headers = {})
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.open_timeout = 10
    http.read_timeout = DEFAULT_TIMEOUT

    request = Net::HTTP::Post.new(uri.request_uri)
    request['Content-Type'] = 'application/json'
    headers.each { |key, value| request[key] = value }
    request.body = body.to_json

    response = http.request(request)
    parsed = JSON.parse(response.body.presence || '{}')
    unless response.is_a?(Net::HTTPSuccess)
      raise "Provider #{@provider} retornou HTTP #{response.code}: #{parsed['error'] || response.message}"
    end

    parsed
  end
end
