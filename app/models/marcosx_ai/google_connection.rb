class MarcosxAi::GoogleConnection < ApplicationRecord
  self.table_name = 'marcosx_ai_google_connections'

  belongs_to :account

  encrypts :access_token if Chatwoot.encryption_configured?
  encrypts :refresh_token if Chatwoot.encryption_configured?

  def connected?
    status == 'connected' && refresh_token.present?
  end

  def redacted
    {
      id: id,
      email: email,
      status: status,
      connected: connected?,
      scopes: scopes || [],
      expires_at: expires_at,
      updated_at: updated_at
    }
  end
end
