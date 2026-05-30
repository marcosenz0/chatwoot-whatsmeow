class Whatsmeow::SessionClient
  class Error < StandardError; end

  def initialize(inbox:)
    @inbox = inbox
    @service_url = ENV.fetch('WHATSMEOW_SERVICE_URL', 'http://whatsmeow-staging:8080')
  end

  def create
    request(
      :post,
      '/sessions',
      body: {
        channel_id: @inbox.id.to_s,
        account_id: @inbox.account_id.to_s
      }
    )
  end

  def status
    request(:get, "/sessions/#{@inbox.id}/status")
  end

  private

  def request(method, path, body: nil)
    response = HTTParty.public_send(
      method,
      "#{@service_url}#{path}",
      body: body&.to_json,
      headers: { 'Content-Type' => 'application/json' },
      timeout: 10
    )

    payload = response.body.present? ? JSON.parse(response.body) : {}
    return payload if response.success?

    raise Error, payload['error'] || response.body
  rescue JSON::ParserError => e
    raise Error, e.message
  end
end
