class MarcosxAi::FailureHandler
  def self.perform(state:, token:, error:)
    state.with_lock do
      return unless state.current_run?(token)

      batch_item_id = state.metadata['reply_batch_item_id']
      state.update!(metadata: state.metadata.except('pending_response', 'pending_since_message_id', 'approved_draft', 'reply_batch_item_id').merge(
        'last_error' => error.message.truncate(500), 'processing' => false, 'run_token' => SecureRandom.uuid
      ))
      state.conversation.messages.create!(
        account: state.account, inbox: state.inbox, sender: state.assistant, message_type: :outgoing, private: true,
        content: I18n.t('marcosx_ai.error_note', name: state.assistant.name, error: error.message.truncate(300)),
        additional_attributes: { marcosx_ai: true }
      )
      MarcosxAi::Log.create!(account: state.account, assistant: state.assistant, conversation: state.conversation,
                             event: 'response_failed', status: 'error', error: error.message.truncate(500))
      if batch_item_id
        item = MarcosxAi::ReplyBatchItem.find(batch_item_id)
        item.update!(status: 'failed', reason: I18n.t('marcosx_ai.errors.batch_failed'))
        item.reply_batch.continue_later
      end
    end
    ChatwootExceptionTracker.new(error, account: state.account).capture_exception
  end
end
