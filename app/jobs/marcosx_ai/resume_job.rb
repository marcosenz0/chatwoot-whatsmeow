class MarcosxAi::ResumeJob < ApplicationJob
  self.queue_adapter = :sidekiq unless Rails.env.test?
  queue_as :default
  discard_on ActiveRecord::RecordNotFound

  def perform(state_id, human_message_id, due)
    state = MarcosxAi::ConversationState.find(state_id)
    state.with_lock do
      return unless state.status == 'paused_by_human' && state.metadata['human_wait'] &&
                    state.last_human_message_id == human_message_id && state.paused_until&.iso8601(6) == due
      return unless state.assistant.resolved_config[:resume_mode] == 'after_human' && state.paused_until <= Time.current

      state.resume!
    end
    latest = MarcosxAi::ConversationContext.public_history(state.conversation).order(:id).last
    MarcosxAi::ResponseScheduler.perform(message: latest) if latest&.incoming?
  end
end
