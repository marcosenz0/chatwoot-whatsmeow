class MarcosxAi::ResponseJob < ApplicationJob
  queue_as :default

  def perform(conversation_id, assistant_id, trigger_message_id)
    conversation = Conversation.find(conversation_id)
    assistant = MarcosxAi::Assistant.find(assistant_id)
    trigger_message = conversation.messages.find_by(id: trigger_message_id)

    return if trigger_message.blank? || !trigger_message.incoming?
    return if human_replied_after?(conversation, trigger_message)

    MarcosxAi::ConversationResponderService.new(
      conversation: conversation,
      assistant: assistant,
      trigger_message: trigger_message
    ).perform
  end

  private

  def human_replied_after?(conversation, trigger_message)
    conversation.messages
                .where('created_at > ?', trigger_message.created_at)
                .where(message_type: :outgoing, private: false, sender_type: 'User')
                .exists?
  end
end
