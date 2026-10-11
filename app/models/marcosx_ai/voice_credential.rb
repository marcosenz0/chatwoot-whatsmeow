class MarcosxAi::VoiceCredential < ApplicationRecord
  self.table_name = 'marcosx_ai_voice_credentials'
  PROVIDERS = %w[minimax elevenlabs].freeze
  belongs_to :account
  belongs_to :assistant, class_name: 'MarcosxAi::Assistant', inverse_of: :voice_credentials
  encrypts :api_key
  validates :provider, inclusion: { in: PROVIDERS }, uniqueness: { scope: :assistant_id }
  validate :same_account_and_encrypted_storage

  def configured?
    api_key.present?
  end

  def redacted
    { provider: provider, configured: configured? }
  end

  private

  def same_account_and_encrypted_storage
    errors.add(:assistant, 'must belong to the account') if assistant && assistant.account_id != account_id
    errors.add(:api_key, 'requires server encryption') if api_key.present? && !Chatwoot.encryption_configured?
  end
end
