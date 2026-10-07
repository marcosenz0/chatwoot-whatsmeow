class MarcosxAi::ConversationMergeService
  pattr_initialize [:source!, :target!]

  def perform
    ActiveRecord::Base.transaction do
      merge_state
      # Keep activity attached to the preserved conversation before removing the duplicate.
      # rubocop:disable Rails/SkipsModelValidations
      MarcosxAi::Log.where(conversation: source).update_all(conversation_id: target.id)
      # rubocop:enable Rails/SkipsModelValidations
    end
  end

  private

  def merge_state
    states = MarcosxAi::ConversationState.where(conversation_id: [source.id, target.id]).order(:id).lock.to_a
    return if states.empty?

    retained = states.find { |state| state.conversation_id == target.id } || states.first
    paused = states.reject { |state| state.status == 'active' }
    decision = paused.find { |state| state.paused_until.nil? } || paused.max_by(&:paused_until) || retained
    metadata = decision.metadata.except('pending_response', 'pending_since_message_id', 'conversation_summary', 'summary_cursor')
    retained.update!(
      conversation: target, assistant: decision.assistant, status: decision.status, paused_until: decision.paused_until,
      last_human_message_id: states.filter_map(&:last_human_message_id).max,
      last_ai_message_id: states.filter_map(&:last_ai_message_id).max,
      metadata: metadata.merge('run_token' => SecureRandom.uuid, 'processing' => false)
    )
    states.reject { |state| state.id == retained.id }.each(&:destroy!)
  end
end
