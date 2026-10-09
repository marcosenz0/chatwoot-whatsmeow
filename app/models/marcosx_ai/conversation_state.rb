class MarcosxAi::ConversationState < ApplicationRecord
  self.table_name = 'marcosx_ai_conversation_states'

  STATUSES = %w[active paused_by_human paused_by_agent awaiting_human handoff error].freeze

  belongs_to :account
  belongs_to :assistant, class_name: 'MarcosxAi::Assistant', optional: true
  belongs_to :conversation, inverse_of: :marcosx_ai_conversation_state
  belongs_to :inbox, class_name: '::Inbox'

  validates :status, inclusion: { in: STATUSES }
  # The unique database index makes create_or_find_by! safe under concurrent arrivals.
  validates :conversation_id, presence: true
  after_commit :clear_typing_presence, on: :update
  after_commit :broadcast_state, on: [:create, :update]

  def self.for_conversation!(conversation, assistant: nil)
    state = create_or_find_by!(conversation: conversation) do |record|
      record.account = conversation.account
      record.inbox = conversation.inbox
      record.assistant = assistant
      record.status = 'paused_by_agent' if assistant && !assistant.feature_enabled?(:auto_start)
    end
    if assistant && state.assistant_id != assistant.id
      state.with_lock do
        metadata = state.metadata.except('pending_response', 'pending_since_message_id', 'manual_activation')
        state.update!(assistant: assistant, metadata: metadata.merge(
          'run_token' => SecureRandom.uuid, 'processing' => false
        ))
        state.pause_by_agent! unless assistant.feature_enabled?(:auto_start)
      end
    end
    # A failed create attempt can leave its unsaved inverse in the conversation's association cache.
    conversation.association(:marcosx_ai_conversation_state).reset
    state
  end

  def active_for_ai?
    return true if status == 'active'
    return false unless status == 'paused_by_human'
    return false if metadata['human_wait'] && assistant.resolved_config[:resume_mode] != 'after_human'
    return false if paused_until.blank?
    return false if paused_until.future?

    resume!
    true
  end

  def enabled_for_ai?
    assistant.present? && (assistant.auto_response_enabled? || metadata['manual_activation'] == true)
  end

  def self.choose_for_conversation!(conversation, assistant:)
    transaction do
      state = for_conversation!(conversation, assistant: assistant)
      state.with_lock do
        state.update!(metadata: state.metadata.except('conversation_summary', 'summary_cursor', 'analysis', 'manual_activation')
                                     .merge('conversation_override' => true))
        state.pause_by_agent!(reason: 'agent_selected')
      end
      state
    end
  end

  def pause_by_human!(message:, minutes:)
    return if status == 'paused_by_agent'

    waiting = metadata['human_wait'] == true
    if waiting
      minutes = assistant.resolved_config[:resume_mode] == 'after_human' ? assistant.resolved_config[:resume_after_minutes].to_i : 0
    end
    update!(
      status: waiting && minutes.zero? ? 'awaiting_human' : 'paused_by_human',
      paused_until: minutes.positive? ? Time.current + minutes.minutes : nil,
      last_human_message_id: message.id,
      metadata: cancelled_metadata.merge('paused_reason' => 'human_response')
    )
    MarcosxAi::ResumeJob.set(wait_until: paused_until).perform_later(id, message.id, paused_until.iso8601(6)) if waiting && paused_until
  end

  def pause_by_agent!(reason: nil)
    update!(
      status: 'paused_by_agent',
      paused_until: nil,
      metadata: cancelled_metadata.except('human_wait', 'pause_ack').merge('paused_reason' => reason.presence || 'agent_paused')
    )
  end

  def resume!(manual: false)
    data = cancelled_metadata.except('last_error', 'paused_reason', 'handoff_reason', 'human_wait', 'pause_ack')
    data.merge!('manual_activation' => true, 'conversation_override' => true) if manual
    update!(status: 'active', paused_until: nil, metadata: data)
  end

  def handoff!(reason: nil)
    update!(
      status: 'handoff',
      paused_until: nil,
      metadata: cancelled_metadata.merge('handoff_reason' => reason.presence || 'manual_handoff')
    )
  end

  def wait_for_human!(reason:)
    update!(status: 'awaiting_human', paused_until: nil,
            metadata: cancelled_metadata.merge('human_wait' => true, 'handoff_reason' => reason))
  end

  def public_data
    {
      id: id, assistant_id: assistant_id, assistant_name: assistant&.name, status: status, paused_until: paused_until,
      enabled: enabled_for_ai?, available: assistant&.available? || false, manual_activation: metadata['manual_activation'] == true,
      processing: metadata['processing'] == true,
      reason: metadata['last_error'] || metadata['handoff_reason'] || metadata['paused_reason'], updated_at: updated_at
    }
  end

  def current_run?(token)
    (status == 'active' || (status == 'awaiting_human' && metadata['pause_ack']) ||
      (status == 'paused_by_agent' && metadata['approved_draft'])) &&
      metadata['run_token'] == token && assistant&.available? && (enabled_for_ai? || metadata['approved_draft'] == true) &&
      conversation.marcosx_ai_assistant&.id == assistant_id && assistant.accepts_conversation?(conversation) &&
      !conversation.resolved? && !conversation.snoozed? && metadata['assistant_version'] == assistant.updated_at.iso8601(6) && !superseded?
  end

  private

  def superseded?
    newer = conversation.messages.where(private: false).where('id > ?', metadata.fetch('trigger_message_id'))
    newer = newer.where("COALESCE(additional_attributes ->> 'marcosx_ai_operational', 'false') != 'true'")
    newer = newer.where("COALESCE(content_attributes ->> 'historical', 'false') != 'true'")
                 .where.not(content_type: Message.content_types[:voice_call])
    incoming = newer.incoming.where("COALESCE(content_attributes ->> 'deleted', 'false') != 'true'")
                    .where("COALESCE(content_attributes ->> 'is_unsupported', 'false') != 'true'")
    human = newer.outgoing.where("sender_type = 'User' OR content_attributes ->> 'external_echo' = 'true'")
                 .where("content_attributes ->> 'automation_rule_id' IS NULL AND additional_attributes ->> 'campaign_id' IS NULL")
    incoming.exists? || human.exists?
  end

  def cancelled_metadata
    metadata.except('pending_response', 'pending_since_message_id', 'approved_draft', 'pause_ack', 'call_event')
            .merge('run_token' => SecureRandom.uuid, 'processing' => false)
  end

  def clear_typing_presence
    previous = saved_change_to_metadata&.first
    return unless previous && previous['processing']
    return if metadata['processing'] && metadata['run_token'] == previous['run_token']

    Whatsmeow::TypingStatusService.new(conversation: conversation, status: 'off').perform
  end

  def broadcast_state
    conversation.association(:marcosx_ai_conversation_state).reset
    conversation.dispatch_conversation_updated_event
  end
end
