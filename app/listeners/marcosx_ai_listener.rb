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
    MarcosxAi::ResponseScheduler.perform(message: message)
  end

  def pause_conversation_for_human(message)
    assistant = message.inbox.marcosx_ai_assistant
    return if assistant.blank?

    state = MarcosxAi::ConversationState.for_conversation!(message.conversation, assistant: assistant)
    state.with_lock { state.pause_by_human!(message: message, minutes: assistant.human_pause_minutes) }
  end

  def human_response?(message)
    return false unless message.outgoing?
    return false if message.private?
    return false if message.historical?
    return false unless message.sender_type == 'User' || message.content_attributes&.dig('external_echo').present?
    return false if message.content_attributes&.dig('automation_rule_id').present?
    return false if message.additional_attributes&.dig('campaign_id').present?

    true
  end
end
