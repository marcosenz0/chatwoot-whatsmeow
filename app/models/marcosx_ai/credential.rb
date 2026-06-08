class MarcosxAi::Credential < ApplicationRecord
  self.table_name = 'marcosx_ai_credentials'

  PROVIDERS = {
    'openai' => {
      display_name: 'OpenAI',
      default_model: 'gpt-4.1-mini',
      default_api_base: 'https://api.openai.com/v1'
    },
    'groq' => {
      display_name: 'Groq',
      default_model: 'llama-3.3-70b-versatile',
      default_api_base: 'https://api.groq.com/openai/v1'
    },
    'gemini' => {
      display_name: 'Gemini',
      default_model: 'gemini-1.5-flash',
      default_api_base: 'https://generativelanguage.googleapis.com/v1beta'
    }
  }.freeze

  belongs_to :account

  encrypts :api_key if Chatwoot.encryption_configured?

  before_validation :normalize_provider

  validates :account_id, presence: true
  validates :provider, presence: true, inclusion: { in: PROVIDERS.keys }
  validates :provider, uniqueness: { scope: :account_id }

  scope :enabled, -> { where(enabled: true) }

  def configured?
    api_key.present?
  end

  def display_name
    provider_config[:display_name]
  end

  def resolved_model
    model.presence || provider_config[:default_model]
  end

  def resolved_api_base
    api_base.presence || provider_config[:default_api_base]
  end

  def redacted
    {
      id: id,
      provider: provider,
      display_name: display_name,
      model: resolved_model,
      api_base: resolved_api_base,
      enabled: enabled,
      configured: configured?,
      created_at: created_at,
      updated_at: updated_at
    }
  end

  private

  def provider_config
    PROVIDERS.fetch(provider)
  end

  def normalize_provider
    self.provider = provider.to_s.downcase.presence
  end
end
