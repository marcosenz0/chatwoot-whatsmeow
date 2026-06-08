class MarcosxAi::Assistant < ApplicationRecord
  self.table_name = 'marcosx_ai_assistants'

  DEFAULT_CONFIG = {
    provider: 'openai',
    model: 'gpt-4.1-mini',
    temperature: 0.7,
    response_delay_seconds: 3,
    history_limit: 20,
    human_pause_minutes: 60,
    auto_response_enabled: true,
    fallback_message: 'No momento nao consegui processar essa mensagem. Vou chamar uma pessoa para continuar o atendimento.',
    handoff_message: 'Vou transferir essa conversa para uma pessoa do atendimento.'
  }.with_indifferent_access.freeze

  belongs_to :account
  has_many :marcosx_ai_inboxes,
           class_name: 'MarcosxAi::Inbox',
           foreign_key: :assistant_id,
           dependent: :destroy_async,
           inverse_of: :assistant
  has_many :inboxes, through: :marcosx_ai_inboxes
  has_many :messages, as: :sender, dependent: :nullify

  validates :name, presence: true
  validates :account_id, presence: true

  scope :ordered, -> { order(created_at: :desc) }

  def resolved_config
    DEFAULT_CONFIG.merge(config || {}).with_indifferent_access
  end

  def provider
    resolved_config[:provider]
  end

  def model
    resolved_config[:model]
  end

  def temperature
    resolved_config[:temperature].to_f
  end

  def response_delay_seconds
    resolved_config[:response_delay_seconds].to_i.clamp(0, 300)
  end

  def history_limit
    resolved_config[:history_limit].to_i.clamp(1, 100)
  end

  def human_pause_minutes
    resolved_config[:human_pause_minutes].to_i.clamp(1, 10_080)
  end

  def auto_response_enabled?
    ActiveModel::Type::Boolean.new.cast(resolved_config[:auto_response_enabled])
  end

  def fallback_message
    resolved_config[:fallback_message]
  end

  def handoff_message
    resolved_config[:handoff_message]
  end

  def available_name
    name
  end

  def push_event_data
    {
      id: id,
      name: name,
      avatar_url: default_avatar_url,
      description: description,
      created_at: created_at,
      type: 'marcosx_ai_assistant'
    }
  end

  def webhook_data
    push_event_data
  end

  private

  def default_avatar_url
    nil
  end
end
