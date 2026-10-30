class MarcosxAi::CoverageRefreshJob < ApplicationJob
  self.queue_adapter = :sidekiq unless Rails.env.test?
  queue_as :low

  def perform(assistant_id)
    assistant = MarcosxAi::Assistant.find_by(id: assistant_id)
    return unless assistant

    assistant.account.conversations.where(inbox_id: assistant.inboxes.select(:id)).or(
      assistant.account.conversations.where(id: assistant.conversation_states.select(:conversation_id))
    ).includes(:inbox, :contact, :marcosx_ai_conversation_state).find_each(&:dispatch_conversation_updated_event)
  end
end
