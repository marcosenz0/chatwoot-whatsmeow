class MarcosxAi::ConversationState < ApplicationRecord
  self.table_name = 'marcosx_ai_conversation_states'

  STATUSES = %w[active paused_by_human paused_by_agent handoff error].freeze

  belongs_to :account
  belongs_to :assistant, class_name: 'MarcosxAi::Assistant', optional: true
  belongs_to :conversation
  belongs_to :inbox, class_name: '::Inbox'

  validates :status, inclusion: { in: STATUSES }
  # The unique database index makes create_or_find_by! safe under concurrent arrivals.
  validates :conversation_id, presence: true
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
        state.update!(assistant: assistant, metadata: state.metadata.except('pending_response', 'pending_since_message_id').merge(
          'run_token' => SecureRandom.uuid, 'processing' => false
        ))
        state.pause_by_agent! unless assistant.feature_enabled?(:auto_start)
      end
    end
    state
  end

  def active_for_ai?
    return true if status == 'active'
    return false unless status == 'paused_by_human'
    return false if paused_until.blank?
    return false if paused_until.future?

    update!(status: 'active', paused_until: nil)
    true
  end

  def pause_by_human!(message:, minutes:)
    update!(
      status: 'paused_by_human',
      paused_until: minutes.positive? ? Time.current + minutes.minutes : nil,
      last_human_message_id: message.id,
      metadata: cancelled_metadata.merge('paused_reason' => 'human_response')
    )
  end

  def pause_by_agent!(reason: nil)
    update!(
      status: 'paused_by_agent',
      paused_until: nil,
      metadata: cancelled_metadata.merge('paused_reason' => reason.presence || 'agent_paused')
    )
  end

  def resume!
    update!(status: 'active', paused_until: nil, metadata: cancelled_metadata.except('last_error', 'paused_reason', 'handoff_reason'))
  end

  def handoff!(reason: nil)
    update!(
      status: 'handoff',
      paused_until: nil,
      metadata: cancelled_metadata.merge('handoff_reason' => reason.presence || 'manual_handoff')
    )
  end

  def public_data
    {
      id: id, assistant_id: assistant_id, assistant_name: assistant&.name, status: status, paused_until: paused_until,
      enabled: assistant&.auto_response_enabled?, processing: metadata['processing'] == true,
      reason: metadata['last_error'] || metadata['handoff_reason'] || metadata['paused_reason'], updated_at: updated_at
    }
  end

  def current_run?(token)
    status == 'active' && metadata['run_token'] == token && assistant&.auto_response_enabled? &&
      conversation.inbox.marcosx_ai_assistant&.id == assistant_id && assistant.accepts_conversation?(conversation) &&
      !conversation.resolved? && !conversation.snoozed? && metadata['assistant_version'] == assistant.updated_at.iso8601(6) && !superseded?
  end

  private

  def superseded?
    newer = conversation.messages.where(private: false).where('id > ?', metadata.fetch('trigger_message_id'))
    newer = newer.where("COALESCE(content_attributes ->> 'historical', 'false') != 'true'")
                 .where.not(content_type: Message.content_types[:voice_call])
    incoming = newer.incoming.where("COALESCE(content_attributes ->> 'deleted', 'false') != 'true'")
                    .where("COALESCE(content_attributes ->> 'is_unsupported', 'false') != 'true'")
    human = newer.outgoing.where("sender_type = 'User' OR content_attributes ->> 'external_echo' = 'true'")
                 .where("content_attributes ->> 'automation_rule_id' IS NULL AND additional_attributes ->> 'campaign_id' IS NULL")
    incoming.exists? || human.exists?
  end

  def cancelled_metadata
    metadata.except('pending_response', 'pending_since_message_id').merge('run_token' => SecureRandom.uuid, 'processing' => false)
  end

  def broadcast_state
    conversation.dispatch_conversation_updated_event
  end
end
