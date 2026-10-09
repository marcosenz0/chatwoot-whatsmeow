class MarcosxAi::MissedCallJob < ApplicationJob
  self.queue_adapter = :sidekiq unless Rails.env.test?
  queue_as :default
  discard_on ActiveRecord::RecordNotFound

  def perform(call_id)
    call = WhatsmeowCall.find(call_id)
    call.with_lock do
      return if call.ai_processed_at || call.direction != 'incoming' || call.connected_at || !call.status.in?(%w[missed declined])

      call.update!(ai_processed_at: Time.current)
      conversation = call.conversation
      assistant = conversation&.marcosx_ai_assistant
      return unless assistant&.feature_enabled?(:reply_to_missed_calls) && assistant.accepts_conversation?(conversation)
      return if conversation.resolved? || conversation.snoozed?

      existing = conversation.marcosx_ai_conversation_state
      return unless assistant.auto_response_enabled? || (existing&.assistant_id == assistant.id && existing.metadata['manual_activation'] == true)

      state = MarcosxAi::ConversationState.for_conversation!(conversation, assistant: assistant)
      state.with_lock do
        return unless state.enabled_for_ai? && state.active_for_ai?

        subsequent = MarcosxAi::ConversationContext.public_history(conversation).where('created_at >= ?', call.ended_at)
        return if subsequent.incoming.exists? || subsequent.outgoing.where(
          "sender_type = 'User' OR #{MarcosxAi::ConversationContext::CONTENT_ATTRIBUTES_SQL} ->> 'external_echo' = 'true'"
        ).exists?

        trigger = conversation.messages.find_by!(source_id: "whatsmeow-call:#{call.source_id}")
        token = SecureRandom.uuid
        state.update!(metadata: state.metadata.except('pending_response', 'approved_draft').merge(
          'run_token' => token, 'trigger_message_id' => trigger.id, 'pending_since_message_id' => trigger.id,
          'manual' => false, 'processing' => true, 'assistant_version' => assistant.updated_at.iso8601(6),
          'call_event' => { id: call.source_id, status: call.status, video: call.video, ended_at: call.ended_at.iso8601 }
        ))
        MarcosxAi::ResponseJob.set(wait: assistant.response_delay_seconds.seconds).perform_later(
          conversation.id, assistant.id, trigger.id, token
        )
      end
    end
  end
end
