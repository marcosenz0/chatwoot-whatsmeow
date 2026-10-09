class MarcosxAiListener < BaseListener
  def message_created(event)
    message = extract_message_and_account(event)[0]
    return if message.additional_attributes['marcosx_ai_operational'] || message.content.to_s.start_with?(MarcosxAi::AlertService::NOTICE_PREFIX)

    if message.incoming?
      schedule_ai_response(message)
    elsif human_response?(message)
      pause_conversation_for_human(message)
    end
  end

  def message_updated(event)
    message = extract_message_and_account(event)[0]
    return unless message.additional_attributes['marcosx_ai_operational']

    delivery = MarcosxAi::AlertDelivery.find_by(message_id: message.id)
    return unless delivery

    delivery.with_lock do
      return if delivery.status == message.status

      delivery.update!(status: message.status, error: message.content_attributes['external_error'])
      if message.failed?
        MarcosxAi::Log.create!(account: delivery.alert.account, assistant: delivery.alert.assistant, conversation: delivery.alert.conversation,
                               event: 'notification_failed', response: { delivery_id: delivery.id })
      end
    end
  end

  private

  def schedule_ai_response(message)
    MarcosxAi::ResponseScheduler.perform(message: message)
  end

  def pause_conversation_for_human(message)
    assistant = message.conversation.marcosx_ai_assistant
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
