class MarcosxAiListener < BaseListener
  def message_created(event)
    message = extract_message_and_account(event)[0]

    if message.incoming?
      schedule_ai_response(message)
    elsif human_response?(message)
      pause_conversation_for_human(message)
    end
  end

  private

  def schedule_ai_response(message)
    assistant = message.inbox.marcosx_ai_assistant
    return if assistant.blank?
    return unless assistant.auto_response_enabled?

    state = MarcosxAi::ConversationState.for_conversation!(message.conversation, assistant: assistant)
    return unless state.active_for_ai?

    MarcosxAi::ResponseJob.set(wait: assistant.response_delay_seconds.seconds).perform_later(
      message.conversation_id,
      assistant.id,
      message.id
    )
  end

  def pause_conversation_for_human(message)
    assistant = message.inbox.marcosx_ai_assistant
    return if assistant.blank?

    state = MarcosxAi::ConversationState.for_conversation!(message.conversation, assistant: assistant)
    state.pause_by_human!(message: message, minutes: assistant.human_pause_minutes)
  end

  def human_response?(message)
    return false unless message.outgoing?
    return false if message.private?
    return false unless message.sender_type == 'User' || message.content_attributes&.dig('external_echo').present?
    return false if message.content_attributes&.dig('automation_rule_id').present?
    return false if message.additional_attributes&.dig('campaign_id').present?

    true
  end
end
