class MarcosxAi::TypingPresenceJob < ApplicationJob
  self.queue_adapter = :sidekiq unless Rails.env.test?
  queue_as :default
  discard_on ActiveRecord::RecordNotFound

  # WhatsApp presence expires even while a provider request is still running.
  def perform(conversation_id, token)
    state = MarcosxAi::ConversationState.find_by!(conversation_id: conversation_id)
    state.with_lock do
      return unless state.metadata['run_token'] == token
      return unless state.inbox.channel_type == 'Channel::Whatsmeow'

      active = state.metadata['processing'] && state.current_run?(token) && state.assistant.feature_enabled?(:show_typing)
      Whatsmeow::TypingStatusService.new(conversation: state.conversation, status: active ? 'on' : 'off').perform
      self.class.set(wait: 8.seconds).perform_later(conversation_id, token) if active && state.inbox.channel.typing_enabled?
    end
  end
end
