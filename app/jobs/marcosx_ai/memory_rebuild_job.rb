class MarcosxAi::MemoryRebuildJob < ApplicationJob
  self.queue_adapter = :sidekiq unless Rails.env.test?
  queue_as :default
  discard_on ActiveRecord::RecordNotFound

  def perform(id, token)
    state = MarcosxAi::ConversationState.find(id)
    return unless state.metadata.dig('memory_rebuild', 'id') == token

    assistant = state.assistant
    client = MarcosxAi::ProviderClient.new(account: state.account, provider: assistant.provider, model: assistant.model,
                                           temperature: assistant.temperature, reasoning_effort: assistant.reasoning_effort)
    latest = MarcosxAi::ConversationContext.public_history(state.conversation).order(:id).last
    valid = -> { state.reload.metadata.dig('memory_rebuild', 'id') == token }
    if latest
      MarcosxAi::ConversationContext.new(conversation: state.conversation, assistant: assistant, state: state, client: client,
                                         trigger_message: latest, token: token, valid_run: valid).messages
    end
    state.with_lock do
      return unless valid.call

      state.update!(metadata: state.metadata.merge('memory_rebuild' => { 'id' => token, 'status' => 'ready' }))
    end
  rescue StandardError => e
    state&.with_lock do
      return unless state.metadata.dig('memory_rebuild', 'id') == token

      state.update!(metadata: state.metadata.merge('memory_rebuild' => { 'id' => token, 'status' => 'failed', 'error' => e.class.name }))
    end
  end
end
