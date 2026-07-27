class Whatsapp::HealthService
  BASE_URI = 'https://graph.facebook.com'.freeze

  def initialize(channel)
    @channel = channel
    @access_token = channel.provider_config['api_key']
    @api_version = GlobalConfigService.load('WHATSAPP_API_VERSION', 'v22.0')
  end

  def fetch_health_status
    validate_channel!
    fetch_phone_health_data
      .merge(fetch_webhook_subscription_health)
      .merge(fetch_app_credentials_health)
  end

  private

  def validate_channel!
    raise ArgumentError, 'Channel is required' if @channel.blank?
    raise ArgumentError, 'API key is missing' if @access_token.blank?
    raise ArgumentError, 'Phone number ID is missing' if @channel.provider_config['phone_number_id'].blank?
  end

  def fetch_phone_health_data
    phone_number_id = @channel.provider_config['phone_number_id']

    response = HTTParty.get(
      "#{BASE_URI}/#{@api_version}/#{phone_number_id}",
      query: {
        fields: health_fields,
        access_token: @access_token
      }
    )

    handle_response(response)
  rescue StandardError => e
    Rails.logger.error "[WHATSAPP HEALTH] Error fetching health data: #{e.message}"
    raise e
  end

  def health_fields
    %w[
      id
      quality_rating
      messaging_limit_tier
      code_verification_status
      account_mode
      display_phone_number
      name_status
      verified_name
      webhook_configuration
      throughput
      last_onboarded_time
      platform_type
      certificate
    ].join(',')
  end

  def handle_response(response)
    unless response.success?
      error_message = "WhatsApp API request failed: #{response.code} - #{response.body}"
      Rails.logger.error "[WHATSAPP HEALTH] #{error_message}"
      raise error_message
    end

    data = response.parsed_response
    format_health_response(data)
  end

  def format_health_response(response)
    {
      id: response['id'],
      display_phone_number: response['display_phone_number'],
      verified_name: response['verified_name'],
      name_status: response['name_status'],
      quality_rating: response['quality_rating'],
      messaging_limit_tier: response['messaging_limit_tier'],
      account_mode: response['account_mode'],
      code_verification_status: response['code_verification_status'],
      webhook_configuration: response['webhook_configuration'],
      expected_webhook_url: build_expected_webhook_url,
      throughput: response['throughput'],
      last_onboarded_time: response['last_onboarded_time'],
      platform_type: response['platform_type'],
      certificate: response['certificate'],
      business_id: @channel.provider_config['business_account_id']
    }
  end

  def build_expected_webhook_url
    frontend_url = ENV.fetch('FRONTEND_URL', nil)
    return nil if frontend_url.blank?

    "#{frontend_url}/webhooks/whatsapp/#{@channel.phone_number}"
  end

  def fetch_webhook_subscription_health
    configured_app_id = GlobalConfigService.load('WHATSAPP_APP_ID', '').to_s
    waba_id = @channel.provider_config['business_account_id']
    return subscription_health(configured_app_id, [], false) if waba_id.blank?

    response = Whatsapp::FacebookApiClient.new(@access_token).fetch_subscribed_apps(waba_id)
    subscribed_app_ids = response.fetch('data', []).filter_map do |app|
      app.dig('whatsapp_business_api_data', 'id') || app['id']
    end.map(&:to_s).uniq

    subscription_health(configured_app_id, subscribed_app_ids, true)
  rescue StandardError => e
    Rails.logger.error "[WHATSAPP HEALTH] Error fetching subscribed apps: #{e.message}"
    subscription_health(configured_app_id, [], false)
  end

  def subscription_health(configured_app_id, subscribed_app_ids, available)
    {
      webhook_subscription_available: available,
      configured_app_id: configured_app_id,
      subscribed_app_ids: subscribed_app_ids,
      configured_app_subscribed: configured_app_id.present? && subscribed_app_ids.include?(configured_app_id)
    }
  end

  def fetch_app_credentials_health
    configured_app_id = GlobalConfigService.load('WHATSAPP_APP_ID', '').to_s
    response = Whatsapp::FacebookApiClient.new(@access_token).debug_token(@access_token)
    token_data = response.fetch('data', {})
    token_app_id = token_data['app_id'].to_s

    {
      app_credentials_available: true,
      access_token_valid: token_data['is_valid'] == true,
      access_token_app_id: token_app_id,
      access_token_matches_configured_app: configured_app_id.present? && token_app_id == configured_app_id
    }
  rescue StandardError => e
    Rails.logger.error "[WHATSAPP HEALTH] Error validating app credentials: #{e.message}"
    {
      app_credentials_available: false,
      access_token_valid: false,
      access_token_app_id: nil,
      access_token_matches_configured_app: false
    }
  end
end
