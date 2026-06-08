class Api::V1::Accounts::MarcosxAi::PreferencesController < Api::V1::Accounts::MarcosxAi::BaseController
  before_action :ensure_admin!, only: [:update]

  DEFAULT_FEATURES = {
    auto_response: true,
    playground: true,
    google_oauth: true,
    gmail_tools: false,
    calendar_tools: false
  }.with_indifferent_access.freeze

  DEFAULT_SETTINGS = {
    default_provider: 'openai',
    default_model: 'gpt-4.1-mini',
    temperature: 0.7,
    response_delay_seconds: 3,
    history_limit: 20,
    human_pause_minutes: 60
  }.with_indifferent_access.freeze

  def show
    render json: payload
  end

  def update
    save_account_preferences!(preferences_params)
    render json: payload
  end

  private

  def payload
    {
      providers: MarcosxAi::Credential::PROVIDERS,
      features: DEFAULT_FEATURES.deep_merge(account_preferences[:features] || {}),
      settings: DEFAULT_SETTINGS.deep_merge(account_preferences[:settings] || {}),
      credentials: Current.account.marcosx_ai_credentials.order(:provider).map(&:redacted),
      google_connection: Current.account.marcosx_ai_google_connection&.redacted
    }
  end

  def preferences_params
    params.permit(
      features: [:auto_response, :playground, :google_oauth, :gmail_tools, :calendar_tools],
      settings: [:default_provider, :default_model, :temperature, :response_delay_seconds, :history_limit, :human_pause_minutes]
    ).to_h
  end
end
