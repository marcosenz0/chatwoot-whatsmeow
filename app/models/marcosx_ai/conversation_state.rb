class MarcosxAi::ConversationState < ApplicationRecord
  self.table_name = 'marcosx_ai_conversation_states'

  STATUSES = %w[active paused_by_human paused_by_agent handoff error].freeze

  belongs_to :account
  belongs_to :assistant, class_name: 'MarcosxAi::Assistant', optional: true
  belongs_to :conversation
  belongs_to :inbox

  validates :status, inclusion: { in: STATUSES }
  validates :conversation_id, uniqueness: true

  def self.for_conversation!(conversation, assistant: nil)
    state = find_or_initialize_by(conversation: conversation)
    if state.new_record?
      state.account = conversation.account
      state.inbox = conversation.inbox
    end
    state.assistant = assistant if assistant.present? && state.assistant_id != assistant.id
    state.save! if state.changed?
    state
  end

  def active_for_ai?
    return true if status == 'active'
    return false if paused_until.blank?
    return false if paused_until.future?

    update!(status: 'active', paused_until: nil)
    true
  end

  def pause_by_human!(message:, minutes:)
    update!(
      status: 'paused_by_human',
      paused_until: Time.current + minutes.minutes,
      last_human_message_id: message.id,
      metadata: metadata.merge('paused_reason' => 'human_response')
    )
  end

  def pause_by_agent!(minutes:, reason: nil)
    update!(
      status: 'paused_by_agent',
      paused_until: Time.current + minutes.minutes,
      metadata: metadata.merge('paused_reason' => reason.presence || 'agent_paused')
    )
  end

  def resume!
    update!(status: 'active', paused_until: nil)
  end

  def handoff!(reason: nil)
    update!(
      status: 'handoff',
      paused_until: nil,
      metadata: metadata.merge('handoff_reason' => reason.presence || 'manual_handoff')
    )
  end
end
