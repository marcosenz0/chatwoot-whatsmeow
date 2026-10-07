class MarcosxAi::FailureHandler
  def self.perform(state:, token:, error:)
    state.with_lock do
      return unless state.current_run?(token)

      state.update!(status: 'error', paused_until: nil, metadata: state.metadata.except('pending_response').merge(
        'last_error' => error.message.truncate(500), 'processing' => false, 'run_token' => SecureRandom.uuid
      ))
      state.conversation.messages.create!(
        account: state.account, inbox: state.inbox, sender: state.assistant, message_type: :outgoing, private: true,
        content: I18n.t('marcosx_ai.error_note', name: state.assistant.name, error: error.message.truncate(300)),
        additional_attributes: { marcosx_ai: true }
      )
      MarcosxAi::Log.create!(account: state.account, assistant: state.assistant, conversation: state.conversation,
                             event: 'response_failed', status: 'error', error: error.message.truncate(500))
    end
    ChatwootExceptionTracker.new(error, account: state.account).capture_exception
  end
end
