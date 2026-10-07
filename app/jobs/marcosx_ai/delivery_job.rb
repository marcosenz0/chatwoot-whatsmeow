class MarcosxAi::DeliveryJob < ApplicationJob
  queue_as :default
  discard_on ActiveRecord::RecordNotFound

  def perform(conversation_id, token, part_index)
    @state = MarcosxAi::ConversationState.find_by!(conversation_id: conversation_id)
    @state.with_lock do
      return unless @state.current_run?(token)

      plan = @state.metadata['pending_response']
      return unless plan && plan['next_part'] == part_index

      react(plan) if part_index.zero?
      message = create_message(plan['messages'][part_index]) if part_index < plan['messages'].size
      @state.update!(last_ai_message_id: message.id) if message
      if part_index + 1 >= plan['messages'].size
        finish(plan)
      else
        @state.update!(metadata: @state.metadata.merge('pending_response' => plan.merge('next_part' => part_index + 1)))
        self.class.set(wait: @state.assistant.message_interval_seconds.seconds).perform_later(conversation_id, token, part_index + 1)
      end
    end
  rescue StandardError => e
    MarcosxAi::FailureHandler.perform(state: @state, token: token, error: e) if @state
  end

  private

  def react(plan)
    return unless @state.assistant.feature_enabled?(:allow_reactions) && @state.inbox.channel_type == 'Channel::Whatsmeow'
    return unless MarcosxAi::ReplyPlan::REACTIONS.include?(plan['reaction'])

    target = @state.conversation.messages.incoming.find_by(id: plan['reaction_message_id'])
    if target.blank? || target.source_id.blank? || target.content_attributes['deleted']
      raise CustomExceptions::MarcosxAi, I18n.t('marcosx_ai.errors.invalid_response') if plan['messages'].empty?

      return
    end

    Whatsmeow::ReactionService.new(message: target, emoji: plan['reaction'], actor: @state.assistant).perform
  end

  def create_message(content)
    executed_by = Current.executed_by
    Current.executed_by = @state.assistant
    @state.conversation.messages.create!(
      message_type: :outgoing, account: @state.account, inbox: @state.inbox, sender: @state.assistant, content: content,
      additional_attributes: { marcosx_ai: true, provider: @state.assistant.provider, model: @state.assistant.model,
                               trigger_message_id: @state.metadata['trigger_message_id'] }
    )
  ensure
    Current.executed_by = executed_by
  end

  def finish(plan)
    @state.update!(metadata: @state.metadata.except('pending_response', 'pending_since_message_id').merge(
      'processing' => false, 'last_processed_trigger_id' => @state.metadata['trigger_message_id']
    ))
    if plan['handoff']
      @state.handoff!(reason: plan['handoff_reason'])
      @state.conversation.bot_handoff! if @state.conversation.pending?
      @state.conversation.messages.create!(
        account: @state.account, inbox: @state.inbox, sender: @state.assistant, message_type: :outgoing, private: true,
        content: I18n.t('marcosx_ai.handoff_note', name: @state.assistant.name, reason: plan['handoff_reason']),
        additional_attributes: { marcosx_ai: true }
      )
    end
    MarcosxAi::Log.create!(account: @state.account, assistant: @state.assistant, conversation: @state.conversation,
                           event: plan['handoff'] ? 'handoff' : 'response_sent',
                           response: { parts: plan['messages'].size, reaction: plan['reaction'] })
  end
end
