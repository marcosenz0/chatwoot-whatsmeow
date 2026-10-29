class MarcosxAi::Credential < ApplicationRecord
  self.table_name = 'marcosx_ai_credentials'

  PROVIDERS = {
    'openai' => {
      display_name: 'OpenAI',
      default_model: 'gpt-6.1-sol',
      default_api_base: 'https://api.openai.com/v1'
    },
    'groq' => {
      display_name: 'Groq',
      default_model: 'qwen/qwen3.8-27b',
      default_api_base: 'https://api.groq.com/openai/v1'
    },
    'gemini' => {
      display_name: 'Gemini',
      default_model: 'gemini-2.5-flash',
      default_api_base: 'https://generativelanguage.googleapis.com/v1beta'
    }
  }.freeze

  belongs_to :account

  encrypts :api_key if Chatwoot.encryption_configured?

  before_validation :normalize_provider

  validates :account_id, presence: true
  validates :provider, presence: true, inclusion: { in: PROVIDERS.keys }
  validates :name, presence: true, length: { maximum: 80 }, uniqueness: { scope: [:account_id, :provider] }

  scope :enabled, -> { where(enabled: true) }

  def self.for_provider(account, provider, id: nil)
    return account.marcosx_ai_credentials.find_by!(id: id, provider: provider) if id

    credential = account.marcosx_ai_credentials.where(provider: provider).order(:id).first
    return credential if credential&.configured? || credential&.enabled == false
    return credential unless %w[groq openai].include?(provider)

    hook = account.hooks.enabled.find_by(app_id: 'audio_transcription')
    settings = hook&.settings || {}
    return credential if settings["#{provider}_api_key"].blank?

    new(
      account_id: account.id, provider: provider, api_key: settings["#{provider}_api_key"], enabled: true,
      api_base: settings["#{provider}_api_base"].presence,
      created_at: hook.created_at, updated_at: hook.updated_at
    )
  end

  def self.connections_for(account)
    saved = account.marcosx_ai_credentials.order(:id).to_a
    inherited = PROVIDERS.keys.filter_map { |provider| for_provider(account, provider) unless saved.any? { |item| item.provider == provider } }
    [*saved, *inherited].map do |credential|
      result = credential.redacted
      unless credential.persisted?
        states = account.marcosx_ai_assistants.pluck(:connection_status).flat_map(&:values)
        latest = states.select { |state|
          state.dig('connections', "integration:#{credential.provider}") && state['checked_at'].to_s >= credential.updated_at.iso8601
        }
                       .max_by { |state| state['checked_at'].to_s }
        result[:health] = latest&.dig('connections', "integration:#{credential.provider}") || {}
      end
      result
    end
  end

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
      name: name,
      provider: provider,
      display_name: display_name,
      model: resolved_model,
      api_base: resolved_api_base,
      enabled: enabled,
      configured: configured?,
      source: persisted? ? 'marcosx_ai' : 'integration',
      health: health,
      created_at: created_at,
      updated_at: updated_at
    }
  end

  def record_health!(error: nil)
    status = if error
               delay = error.retry_after || (error.provider_status.in?([401, 402, 403]) ? 300 : 60)
               { 'state' => 'error', 'error' => error.message.truncate(300), 'status' => error.provider_status,
                 'failed_at' => Time.current.iso8601, 'retry_at' => (Time.current + delay.clamp(1, 3600).seconds).iso8601 }
             else
               { 'state' => 'healthy', 'checked_at' => Time.current.iso8601 }
             end
    self.health = status
    if persisted?
      update_columns(health: status)
    else
      record_inherited_health(status)
    end
    status
  end

  private

  def record_inherited_health(status)
    key = "integration:#{provider}"
    account.marcosx_ai_assistants.find_each do |assistant|
      assistant.with_lock do
        states = assistant.connection_status.deep_dup
        changed = false
        states.each_value do |state|
          next unless state.dig('connections', key)

          state['connections'][key] = state['connections'][key].slice('provider', 'name', 'role').merge(status)
          state['checked_at'] = Time.current.iso8601
          changed = true
        end
        assistant.update_columns(connection_status: states) if changed
      end
    end
  end

  def provider_config
    PROVIDERS.fetch(provider)
  end

  def normalize_provider
    self.provider = provider.to_s.downcase.presence
  end
end
