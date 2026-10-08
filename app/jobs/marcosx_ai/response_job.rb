class MarcosxAi::ResponseJob < ApplicationJob
  # Scheduled AI replies must survive process restarts, including installs using async for UI jobs.
  self.queue_adapter = :sidekiq unless Rails.env.test?
  queue_as :default
  discard_on ActiveRecord::RecordNotFound

  def perform(conversation_id, assistant_id, trigger_message_id, token = nil)
    conversation = Conversation.find(conversation_id)
    assistant = MarcosxAi::Assistant.find(assistant_id)
    trigger_message = conversation.messages.find_by(id: trigger_message_id)

    return if trigger_message.blank? || token.blank?

    MarcosxAi::ConversationResponderService.new(
      conversation: conversation,
      assistant: assistant,
      trigger_message: trigger_message,
      token: token
    ).perform
  end
end
