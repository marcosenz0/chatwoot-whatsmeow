class MarcosxAi::Assistant < ApplicationRecord
  self.table_name = 'marcosx_ai_assistants'

  DEFAULT_CONFIG = {
    provider: 'openai',
    model: 'gpt-6.1-sol',
    connection_id: nil, max_output_tokens: nil,
    fallback: { enabled: false, retry_primary: true, provider: 'openai', connection_id: nil, max_output_tokens: nil, model: 'gpt-6-luna' },
    temperature: 0.7,
    reasoning_effort: 'medium',
    response_delay_seconds: 8,
    history_limit: 80,
    prompt_cache: { enabled: true, ttl: '30m' },
    timezone: nil,
    human_pause_minutes: 0,
    memory_mode: 'legacy',
    editorial_instructions: nil,
    reply_to_missed_calls: false,
    missed_call_instructions: 'Responda brevemente por texto à ligação não atendida e continue o assunto da conversa.',
    notifications: { user_ids: [], whatsapp_numbers: [], inbox_id: nil },
    alert_rules: [],
    resume_mode: 'manual',
    resume_after_minutes: 60,
    pause_on_handoff: false,
    pause_acknowledgement: true,
    auto_response_enabled: false,
    manual_sessions_enabled: true,
    auto_start: true,
    show_typing: true,
    show_recording: true,
    split_messages: true,
    emoji_usage: 'occasional',
    voice: {
      enabled: false, provider: 'minimax', mode: 'requested', send_text: false, max_characters: 1500,
      min_text_turns: 6, long_message_characters: 450,
      instructions: 'Use português brasileiro e frases curtas. Escreva números, datas e horários por extenso.',
      pronunciation: '',
      minimax: { voice_id: '', model: 'speech-2.8-hd', speed: 1.0, volume: 1.0, pitch: 0 },
      elevenlabs: { voice_id: '', model: 'eleven_multilingual_v2', speed: 1.0, stability: 0.5, similarity_boost: 0.75, style: 0.0 }
    },
    max_message_parts: 3,
    message_target_characters: 160,
    separate_greeting: true,
    message_interval_seconds: 2,
    allow_reactions: true,
    process_images: true,
    vision: { provider: 'agent', model: '', connection_id: nil, max_output_tokens: nil, max_dimension: 1600, video_frames: 3,
              video_interval_seconds: 5, instructions: '',
              fallback: { enabled: false, retry_primary: true, provider: 'openai', connection_id: nil, max_output_tokens: nil,
                          model: 'gpt-6-luna' } },
    process_audio: true,
    transcription: { provider: 'agent', model: '', connection_id: nil, max_output_tokens: nil,
                     fallback: { enabled: false, retry_primary: true, provider: 'openai', connection_id: nil, max_output_tokens: nil,
                                 model: 'gpt-4o-transcribe' } },
    process_files: true,
    process_video: true,
    respond_to_groups: false,
    fallback_message: 'No momento nao consegui processar essa mensagem. Vou chamar uma pessoa para continuar o atendimento.',
    handoff_message: 'Vou transferir essa conversa para uma pessoa do atendimento.'
  }.with_indifferent_access.freeze

  belongs_to :account
  has_many :marcosx_ai_inboxes,
           class_name: 'MarcosxAi::Inbox',
           foreign_key: :assistant_id,
           dependent: :destroy,
           inverse_of: :assistant
  has_many :inboxes, through: :marcosx_ai_inboxes
  has_many :messages, as: :sender, dependent: :nullify
  has_many :conversation_states, class_name: 'MarcosxAi::ConversationState', dependent: :nullify, inverse_of: :assistant
  has_many :logs, class_name: 'MarcosxAi::Log', dependent: :nullify, inverse_of: :assistant
  has_many :alerts, class_name: 'MarcosxAi::Alert', dependent: :nullify, inverse_of: :assistant
  has_many :voice_credentials, class_name: 'MarcosxAi::VoiceCredential', dependent: :destroy, inverse_of: :assistant
  has_many :pix_keys, class_name: 'MarcosxAi::PixKey', dependent: :destroy, inverse_of: :assistant
  has_many :resources, class_name: 'MarcosxAi::Resource', dependent: :destroy, inverse_of: :assistant
  has_many :reply_batches, class_name: 'MarcosxAi::ReplyBatch', dependent: :destroy

  has_many :notification_targets, class_name: 'MarcosxAi::NotificationTarget', dependent: :destroy, inverse_of: :assistant

  validates :name, presence: true
  validates :account_id, presence: true
  validate :valid_configuration
  after_commit :cancel_pending_runs, on: :update
  after_commit :broadcast_coverage, on: :update

  scope :ordered, -> { order(created_at: :desc) }

  def resolved_config
    settings = DEFAULT_CONFIG.merge(config || {}).with_indifferent_access
    settings[:voice] = DEFAULT_CONFIG[:voice].deep_merge(settings[:voice] || {})
    settings[:prompt_cache] = DEFAULT_CONFIG[:prompt_cache].deep_merge(settings[:prompt_cache] || {})
    settings[:vision] = DEFAULT_CONFIG[:vision].deep_merge(settings[:vision] || {})
    settings[:fallback] = DEFAULT_CONFIG[:fallback].deep_merge(settings[:fallback] || {})
    settings[:transcription] = DEFAULT_CONFIG[:transcription].deep_merge(settings[:transcription] || {})
    settings
  end

  def voice_ready?
    settings = resolved_config[:voice]
    (settings[:enabled] == true && settings.dig(settings[:provider], :voice_id).present? &&
      voice_credentials.find_by(provider: settings[:provider])&.configured?) || false
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
    resolved_config[:history_limit].to_i.clamp(10, 300)
  end

  def human_pause_minutes
    resolved_config[:human_pause_minutes].to_i.clamp(0, 10_080)
  end

  def memory_mode
    resolved_config[:memory_mode]
  end

  def alert_rules
    resolved_config[:alert_rules].map(&:with_indifferent_access)
  end

  def auto_response_enabled?
    ActiveModel::Type::Boolean.new.cast(resolved_config[:auto_response_enabled])
  end

  def available?
    MarcosxAi::ConnectionPlan.new(assistant: self, feature: 'chat').endpoints.any? do |endpoint|
      endpoint[:credential]&.enabled && endpoint[:credential].configured?
    end
  end

  def reasoning_effort
    resolved_config[:reasoning_effort]
  end

  def split_messages?
    ActiveModel::Type::Boolean.new.cast(resolved_config[:split_messages])
  end

  def max_message_parts
    resolved_config[:max_message_parts].to_i.clamp(1, 5)
  end

  def message_interval_seconds
    resolved_config[:message_interval_seconds].to_i.clamp(0, 15)
  end

  def feature_enabled?(feature)
    ActiveModel::Type::Boolean.new.cast(resolved_config[feature])
  end

  def accepts_conversation?(conversation)
    return false unless conversation.can_reply?
    return false if conversation.contact.blocked?

    if conversation.inbox.channel_type.in?(%w[Channel::FacebookPage Channel::Instagram])
      last_incoming = conversation.messages.incoming.order(:created_at, :id).last
      return false unless last_incoming && last_incoming.created_at > 24.hours.ago
    end

    group = conversation.additional_attributes['whatsmeow_group'] || conversation.additional_attributes['telegram_group'] ||
            conversation.contact.additional_attributes['whatsmeow_group'] || conversation.additional_attributes['chat_type'].in?(%w[group supergroup
                                                                                                                                    channel])
    !group || feature_enabled?(:respond_to_groups)
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

  def broadcast_coverage
    MarcosxAi::CoverageRefreshJob.perform_later(id)
  end

  def cancel_pending_runs
    return unless saved_changes?

    suspend_manual = saved_change_to_config? && saved_change_to_config.first.fetch('manual_sessions_enabled', true) &&
                     !feature_enabled?(:manual_sessions_enabled)
    states = conversation_states.where("metadata ->> 'processing' = 'true'")
    states = states.or(conversation_states.where("metadata ->> 'manual_session_override' = 'true'")) if suspend_manual
    states.find_each do |state|
      state.with_lock do
        metadata = state.metadata.except('pending_response', 'pending_since_message_id', 'approved_draft')
        metadata = metadata.except('manual_session_override') if suspend_manual
        state.update!(metadata: metadata.merge(
          'run_token' => SecureRandom.uuid, 'processing' => false
        ))
      end
    end
  end

  def valid_configuration
    errors.add(:config, 'has an invalid provider') unless MarcosxAi::Credential::PROVIDERS.key?(provider)
    errors.add(:config, 'requires a model') if model.blank?
    errors.add(:config, 'has an invalid reasoning effort') unless %w[low medium high].include?(reasoning_effort)
    timezone = resolved_config[:timezone]
    errors.add(:config, 'has an invalid timezone') if timezone.present? && ActiveSupport::TimeZone[timezone].nil?
    return unless auto_response_enabled?

    errors.add(:config, I18n.t('marcosx_ai.errors.credential_missing')) unless available?
  end

  def default_avatar_url
    nil
  end
end
