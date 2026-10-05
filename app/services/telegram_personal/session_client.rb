require 'net/http'

class TelegramPersonal::SessionClient
  class Error < StandardError
    attr_reader :code

    def initialize(code)
      @code = code
      super(code)
    end
  end

  def initialize(inbox:)
    @inbox = inbox
  end

  def connect
    request(:post, '', @inbox.channel.attributes.slice('phone_number', 'ignore_groups', 'ignore_channels'))
  end

  def status = request(:get, '')
  def password(value) = request(:post, '/password', { password: value })
  def disconnect = request(:delete, '')
  def send_message(payload) = request(:post, '/messages', payload)
  def settings(ignore_groups:, ignore_channels:) = request(:patch, '/settings', { ignore_groups: ignore_groups, ignore_channels: ignore_channels })

  def download_media(media_id)
    raise Error, 'invalid_media' unless media_id.to_s.match?(/\A[0-9a-f]{32}\z/)

    response = http_request(:get, "/media/#{media_id}")
    raise Error, 'media_unavailable' unless response.is_a?(Net::HTTPSuccess)

    response.body
  end

  private

  def request(method, path, payload = nil)
    response = http_request(method, path, payload)
    body = JSON.parse(response.body)
    raise Error, body.fetch('error', 'service_unavailable') unless response.is_a?(Net::HTTPSuccess)

    body
  rescue JSON::ParserError, KeyError, SocketError, Timeout::Error, SystemCallError
    raise Error, 'service_unavailable'
  end

  def http_request(method, path, payload = nil)
    url = ENV.fetch('TELEGRAM_PERSONAL_SERVICE_URL')
    uri = URI("#{url.chomp('/')}/sessions/#{@inbox.account_id}/#{@inbox.id}#{path}")
    request = Net::HTTP.const_get(method.to_s.capitalize).new(uri)
    request['Authorization'] = "Bearer #{ENV.fetch('TELEGRAM_PERSONAL_SHARED_SECRET')}"
    request['Content-Type'] = 'application/json'
    request.body = payload.to_json if payload
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 5, read_timeout: 120) do |http|
      http.request(request)
    end
  end
end
