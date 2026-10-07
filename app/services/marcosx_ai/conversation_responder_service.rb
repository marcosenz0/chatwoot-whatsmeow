class MarcosxAi::ConversationResponderService
  def initialize(conversation:, assistant:, trigger_message:, token:)
    @conversation = conversation
    @assistant = assistant
    @trigger_message = trigger_message
    @token = token
    @state = MarcosxAi::ConversationState.find_by!(conversation: conversation)
  end

  def perform
    return unless @state.reload.current_run?(@token)

    client = MarcosxAi::ProviderClient.new(account: @conversation.account, provider: @assistant.provider, model: @assistant.model,
                                           temperature: @assistant.temperature, reasoning_effort: @assistant.reasoning_effort)
    history = MarcosxAi::ConversationContext.new(conversation: @conversation, assistant: @assistant, state: @state, client: client,
                                                 trigger_message: @trigger_message, token: @token).messages
    return unless @state.reload.current_run?(@token)

    prompts = MarcosxAi::PromptBuilder.messages(
      assistant: @assistant, context: { contact: @conversation.contact.name, inbox: @conversation.inbox.name, now: Time.current.iso8601 },
      reactions: @assistant.feature_enabled?(:allow_reactions) && @conversation.inbox.channel_type == 'Channel::Whatsmeow',
      proactive: @state.metadata['manual']
    )
    plan = MarcosxAi::ReplyPlan.parse(client.chat(messages: [*prompts, *history], schema: MarcosxAi::ReplyPlan::SCHEMA), assistant: @assistant)
    plan['messages'] = [@assistant.handoff_message] if plan['handoff'] && plan['messages'].empty? && @assistant.handoff_message.present?
    if plan['messages'].empty? && plan['reaction'].blank? && !plan['handoff']
      raise CustomExceptions::MarcosxAi, I18n.t('marcosx_ai.errors.empty_response')
    end

    @state.with_lock do
      return unless @state.current_run?(@token)

      @state.update!(metadata: @state.metadata.merge('pending_response' => plan.merge('next_part' => 0)))
      MarcosxAi::Log.create!(account: @conversation.account, assistant: @assistant, conversation: @conversation, event: 'response_generated',
                             response: { provider: @assistant.provider, model: @assistant.model, parts: plan['messages'].size,
                                         handoff: plan['handoff'], usage: client.usage })
    end
    MarcosxAi::DeliveryJob.perform_later(@conversation.id, @token, 0)
    plan
  rescue StandardError => e
    MarcosxAi::FailureHandler.perform(state: @state, token: @token, error: e)
    nil
  end
end
