class MarcosxAi::GoogleCallbacksController < ApplicationController
  def show
    token = google_client.auth_code.get_token(
      params[:code],
      redirect_uri: "#{base_url}/marcosx_ai/google/callback"
    )
    parsed = token.response.parsed
    account.marcosx_ai_google_connection&.destroy
    account.create_marcosx_ai_google_connection!(
      email: users_data(parsed)['email'],
      access_token: parsed['access_token'],
      refresh_token: parsed['refresh_token'],
      expires_at: Time.current + parsed['expires_in'].to_i.seconds,
      scopes: parsed['scope'].to_s.split,
      status: 'connected'
    )

    redirect_to "#{base_url}/app/accounts/#{account.id}/captain/google"
  rescue StandardError => e
    ChatwootExceptionTracker.new(e).capture_exception
    redirect_to @account.present? ? "#{base_url}/app/accounts/#{@account.id}/captain/google" : "#{base_url}/app"
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

  def users_data(parsed)
    JWT.decode(parsed['id_token'], nil, false).first
  end

  def account
    @account ||= GlobalID::Locator.locate_signed(params[:state])
  end

  def base_url
    ENV.fetch('FRONTEND_URL', 'http://localhost:3000')
  end
end
