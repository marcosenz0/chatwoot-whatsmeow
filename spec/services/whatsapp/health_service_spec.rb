require 'rails_helper'

RSpec.describe Whatsapp::HealthService do
  let(:channel) do
    create(
      :channel_whatsapp,
      provider: 'whatsapp_cloud',
      validate_provider_config: false,
      sync_templates: false,
      provider_config: {
        'api_key' => 'test-token',
        'phone_number_id' => 'phone-number-id',
        'business_account_id' => 'waba-id'
      }
    )
  end
  let(:facebook_api_client) { instance_double(Whatsapp::FacebookApiClient) }
  let(:phone_health_response) do
    {
      'id' => 'phone-number-id',
      'display_phone_number' => '+55 11 99999-9999',
      'verified_name' => 'Example',
      'quality_rating' => 'GREEN'
    }
  end

  before do
    allow(HTTParty).to receive(:get).and_return(
      instance_double(HTTParty::Response, success?: true, parsed_response: phone_health_response)
    )
    allow(Whatsapp::FacebookApiClient).to receive(:new).with('test-token').and_return(facebook_api_client)
    allow(GlobalConfigService).to receive(:load).and_call_original
    allow(GlobalConfigService).to receive(:load).with('WHATSAPP_API_VERSION', 'v22.0').and_return('v22.0')
    allow(GlobalConfigService).to receive(:load).with('WHATSAPP_APP_ID', '').and_return('app-id')
  end

  it 'reports whether the configured app is subscribed to the WABA' do
    allow(facebook_api_client).to receive(:fetch_subscribed_apps).with('waba-id').and_return(
      'data' => [{ 'whatsapp_business_api_data' => { 'id' => 'app-id' } }]
    )

    health = described_class.new(channel).fetch_health_status

    expect(health).to include(
      webhook_subscription_available: true,
      configured_app_id: 'app-id',
      subscribed_app_ids: ['app-id'],
      configured_app_subscribed: true
    )
  end

  it 'keeps phone health available when the subscription lookup fails' do
    allow(facebook_api_client).to receive(:fetch_subscribed_apps).and_raise('Graph API unavailable')

    health = described_class.new(channel).fetch_health_status

    expect(health).to include(
      webhook_subscription_available: false,
      subscribed_app_ids: [],
      configured_app_subscribed: false
    )
  end
end
