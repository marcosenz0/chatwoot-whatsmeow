class Api::V1::Accounts::MarcosxAi::Google::AuthorizationsController < Api::V1::Accounts::OauthAuthorizationController
  def create
    redirect_url = google_client.auth_code.authorize_url(
      redirect_uri: "#{base_url}/marcosx_ai/google/callback",
      scope: scope,
      response_type: 'code',
      prompt: 'consent',
      access_type: 'offline',
      state: state,
      client_id: GlobalConfigService.load('GOOGLE_OAUTH_CLIENT_ID', nil)
    )

    render json: { success: true, url: redirect_url }
  end

  private

  def google_client
    OAuth2::Client.new(
      GlobalConfigService.load('GOOGLE_OAUTH_CLIENT_ID', nil),
      GlobalConfigService.load('GOOGLE_OAUTH_CLIENT_SECRET', nil),
      site: 'https://oauth2.googleapis.com',
      authorize_url: 'https://accounts.google.com/o/oauth2/auth',
      token_url: 'https://oauth2.googleapis.com/token'
    )
  end

  def scope
    [
      'email',
      'profile',
      'https://www.googleapis.com/auth/gmail.send',
      'https://www.googleapis.com/auth/calendar.events'
    ].join(' ')
  end
end
