class MarcosxAi::ConversationAnalysisJob < ApplicationJob
  self.queue_adapter = :sidekiq unless Rails.env.test?
  queue_as :default
  discard_on ActiveRecord::RecordNotFound

  def perform(state_id, token)
    state = MarcosxAi::ConversationState.find(state_id)
    MarcosxAi::ConversationAnalysisService.new(state: state).perform(token)
  end
end
