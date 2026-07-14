require 'cgi'
require 'net/http'

class Whatsmeow::SessionClient
  class Error < StandardError; end

  DEFAULT_TIMEOUT = 60
  DEFAULT_STATUS_TIMEOUT = 330
  DEFAULT_SERVICE_URLS = [
    'http://whatsmeow-staging:8080',
    'http://marcos-apps_whatsmeow-staging:8080'
  ].freeze
  PRE_CONNECTION_ERRORS = [
    SocketError,
    Net::OpenTimeout,
    Errno::ECONNREFUSED,
    (Errno::EHOSTUNREACH if defined?(Errno::EHOSTUNREACH)),
    (Errno::ENETUNREACH if defined?(Errno::ENETUNREACH))
  ].compact.freeze

  def initialize(inbox:)
    @inbox = inbox
  end

  def create(force_new: false)
    request(
      :post,
      '/sessions',
      body: {
        channel_id: @inbox.id.to_s,
        account_id: @inbox.account_id.to_s,
        force_new: force_new
      }
    )
  end

  def status
    request(:get, "/sessions/#{@inbox.id}/status")
  end

  def check_number(phone)
    request(:get, "/sessions/#{@inbox.id}/check_number?phone=#{CGI.escape(phone)}")
  end

  def disconnect
    request(:delete, "/sessions/#{@inbox.id}")
  end

  def group_members(group_jid)
    request(:get, "/sessions/#{@inbox.id}/group_members?group_jid=#{CGI.escape(group_jid)}")
  end

  def group_invite(code)
    request(:get, "/sessions/#{@inbox.id}/group_invite?code=#{CGI.escape(code)}")
  end

  def join_group_invite(code)
    request(:post, "/sessions/#{@inbox.id}/group_invite", body: { code: code })
  end

  def add_group_member(group_jid:, participant_jid: nil, participant_phone: nil)
    request(
      :post,
      "/sessions/#{@inbox.id}/group_members",
      body: {
        group_jid: group_jid,
        participant_jid: participant_jid,
        participant_phone: participant_phone
      }
    )
  end

  def groups
    request(:get, "/sessions/#{@inbox.id}/groups")
  end

  def profile_picture(jid, force: false)
    path = "/sessions/#{@inbox.id}/profile_picture?jid=#{CGI.escape(jid)}"
    path = "#{path}&force=true" if force

    request(:get, path)
  end

  def resolve_identities(jids)
    request(
      :post,
      "/sessions/#{@inbox.id}/identities/resolve",
      body: { jids: jids }
    )
  end

  def sync_contacts(contacts)
    request(
      :post,
      "/sessions/#{@inbox.id}/contacts/sync",
      body: { contacts: contacts }
    )
  end

  def publish_status(payload)
    request(:post, "/sessions/#{@inbox.id}/statuses", body: payload, timeout: self.class.status_timeout)
  end

  def sync_status_history(message_id:, timestamp:, from_me:)
    request(
      :post,
      "/sessions/#{@inbox.id}/statuses/sync",
      body: { message_id: message_id, timestamp: timestamp, from_me: from_me },
      timeout: 20
    )
  end

  def delete_status(message_id)
    request(:delete, "/sessions/#{@inbox.id}/statuses/#{CGI.escape(message_id)}", timeout: 20)
  end

  def mark_status_read(message_id:, sender_jid:, timestamp:)
    request(
      :post,
      "/sessions/#{@inbox.id}/statuses/read",
      body: { message_id: message_id, sender_jid: sender_jid, timestamp: timestamp },
      timeout: 20
    )
  end

  def reply_to_status(payload)
    request(
      :post,
      "/sessions/#{@inbox.id}/statuses/reply",
      body: payload,
      timeout: 20
    )
  end

  def self.request(method, path, body: nil, timeout: nil)
    last_error = nil

    service_urls.each do |service_url|
      return request_from_service(method, service_url, path, body, timeout)
    rescue *PRE_CONNECTION_ERRORS => e
      last_error = e.message
    rescue Error
      raise
    rescue StandardError => e
      raise Error, e.message
    end

    raise Error, last_error || 'Whatsmeow service request failed'
  end

  def self.request_from_service(method, service_url, path, body, request_timeout)
    response = perform_request(method, service_url, path, body, request_timeout)
    payload = parse_response(response)
    return payload if response.success?

    error_message = payload['error'] if payload.is_a?(Hash)
    raise Error, error_message.presence || response.body.presence || 'Whatsmeow service request failed'
  end

  def self.perform_request(method, service_url, path, body, request_timeout)
    headers = { 'Content-Type' => 'application/json' }
    shared_secret = ENV.fetch('WHATSMEOW_SHARED_SECRET', '')
    headers['X-Whatsmeow-Internal-Token'] = shared_secret if shared_secret.present?

    HTTParty.public_send(
      method,
      "#{service_url}#{path}",
      body: body&.to_json,
      headers: headers,
      timeout: request_timeout || timeout
    )
  end

  def self.timeout
    ENV.fetch('WHATSMEOW_SERVICE_TIMEOUT', DEFAULT_TIMEOUT).to_i
  end

  def self.status_timeout
    ENV.fetch('WHATSMEOW_STATUS_TIMEOUT', DEFAULT_STATUS_TIMEOUT).to_i
  end

  def self.parse_response(response)
    response.body.present? ? JSON.parse(response.body) : {}
  end

  def self.service_urls
    configured_urls = ENV.fetch('WHATSMEOW_SERVICE_URL', '')
                         .split(',')
                         .map(&:strip)
                         .reject(&:blank?)

    configured_urls.present? ? configured_urls.uniq : DEFAULT_SERVICE_URLS
  end

  private

  def request(method, path, body: nil, timeout: nil)
    self.class.request(method, path, body: body, timeout: timeout)
  end
end
