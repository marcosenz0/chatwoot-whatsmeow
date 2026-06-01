class Whatsmeow::SessionClient
  class Error < StandardError; end

  DEFAULT_TIMEOUT = 60
  DEFAULT_SERVICE_URLS = [
    'http://whatsmeow-staging:8080',
    'http://marcos-apps_whatsmeow-staging:8080'
  ].freeze

  def initialize(inbox:)
    @inbox = inbox
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

  def disconnect
    request(:delete, "/sessions/#{@inbox.id}")
  end

  def self.request(method, path, body: nil)
    last_error = nil

    service_urls.each do |service_url|
      response = perform_request(method, service_url, path, body)
      payload = parse_response(response)
      return payload if response.success?

      last_error = payload['error'] || response.body
    rescue StandardError => e
      last_error = e.message
    end

    raise Error, last_error || 'Whatsmeow service request failed'
  end

  def self.perform_request(method, service_url, path, body)
    HTTParty.public_send(
      method,
      "#{service_url}#{path}",
      body: body&.to_json,
      headers: { 'Content-Type' => 'application/json' },
      timeout: timeout
    )
  end

  def self.timeout
    ENV.fetch('WHATSMEOW_SERVICE_TIMEOUT', DEFAULT_TIMEOUT).to_i
  end

  def self.parse_response(response)
    response.body.present? ? JSON.parse(response.body) : {}
  end

  def self.service_urls
    configured_urls = ENV.fetch('WHATSMEOW_SERVICE_URL', '')
                         .split(',')
                         .map(&:strip)
                         .reject(&:blank?)

    (configured_urls + DEFAULT_SERVICE_URLS).uniq
  end

  private

  def request(method, path, body: nil)
    self.class.request(method, path, body: body)
  end
end
