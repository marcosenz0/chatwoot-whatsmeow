class MarcosxAi::ResponseScheduler
  def self.perform(message:, manual: false)
    return if message.private? || message.historical? || message.content_attributes['deleted'] || message.content_attributes['is_unsupported'] ||
              message.content_type == 'voice_call' || message.additional_attributes['marcosx_ai_operational'] ||
              message.content.to_s.start_with?(MarcosxAi::AlertService::NOTICE_PREFIX)
    return unless manual || message.incoming?

    conversation = message.conversation
    assistant = conversation.marcosx_ai_assistant
    return unless assistant && assistant.accepts_conversation?(conversation)
    return if conversation.resolved? || conversation.snoozed?

    existing = conversation.marcosx_ai_conversation_state
    return unless assistant.auto_response_enabled? || (existing&.assistant_id == assistant.id && existing.metadata['manual_activation'] == true)

    state = MarcosxAi::ConversationState.for_conversation!(conversation, assistant: assistant)
    token = nil
    state.with_lock do
      return unless state.enabled_for_ai? && state.active_for_ai?
      return if !manual && state.metadata['last_processed_trigger_id'].to_i >= message.id

      token = SecureRandom.uuid
      metadata = state.metadata.except('pending_response', 'approved_draft').merge(
        'run_token' => token, 'trigger_message_id' => message.id,
        'pending_since_message_id' => state.metadata['pending_since_message_id'] || message.id,
        'manual' => manual, 'processing' => true, 'assistant_version' => assistant.updated_at.iso8601(6)
      )
      state.update!(metadata: metadata)
    end
    MarcosxAi::ResponseJob.set(wait: manual ? 0 : assistant.response_delay_seconds.seconds)
                          .perform_later(conversation.id, assistant.id, message.id, token)
  end
end
