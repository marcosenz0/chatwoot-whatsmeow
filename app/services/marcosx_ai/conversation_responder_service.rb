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

    MarcosxAi::TypingPresenceJob.perform_now(@conversation.id, @token) if @assistant.feature_enabled?(:show_typing)

    client = MarcosxAi::ProviderClient.new(account: @conversation.account, provider: @assistant.provider, model: @assistant.model,
                                           temperature: @assistant.temperature, reasoning_effort: @assistant.reasoning_effort)
    history = MarcosxAi::ConversationContext.new(conversation: @conversation, assistant: @assistant, state: @state, client: client,
                                                 trigger_message: @trigger_message, token: @token).messages
    return unless @state.reload.current_run?(@token)

    prompts = MarcosxAi::PromptBuilder.messages(
      assistant: @assistant, context: MarcosxAi::PromptBuilder.context_for(@conversation, assistant: @assistant),
      reactions: @assistant.feature_enabled?(:allow_reactions) && @conversation.inbox.channel_type == 'Channel::Whatsmeow',
      proactive: @state.metadata['manual']
    )
    if @state.metadata['call_event']
      prompts << { role: 'developer', content: @assistant.resolved_config[:missed_call_instructions] }
      history << { role: 'user', content: "Evento de ligação encerrada sem atendimento (dados): #{@state.metadata['call_event'].to_json}" }
    end
    plan = MarcosxAi::ReplyPlan.parse(client.chat(messages: [*prompts, *history], schema: MarcosxAi::ReplyPlan::SCHEMA), assistant: @assistant)
    if plan['recall_context']
      return unless @state.reload.current_run?(@token)

      recalled = MarcosxAi::LinkedContext.new(state: @state).messages(client: client)
      history.concat(recalled.presence || [{ role: 'user',
                                             content: 'Nenhum histórico de outro canal está aprovado. Peça confirmação ao responsável.' }])
      plan = MarcosxAi::ReplyPlan.parse(client.chat(messages: [*prompts, *history], schema: MarcosxAi::ReplyPlan::SCHEMA), assistant: @assistant)
    end
    plan['messages'] = [@assistant.handoff_message] if plan['handoff'] && plan['messages'].empty? && @assistant.handoff_message.present?
    if plan['messages'].empty? && plan['reaction'].blank? && !plan['handoff'] && plan['alert_rule_ids'].empty?
      raise CustomExceptions::MarcosxAi, I18n.t('marcosx_ai.errors.empty_response')
    end

    @state.with_lock do
      return unless @state.current_run?(@token)

      plan = MarcosxAi::AlertService.prepare_delivery(state: @state, plan: plan, token: @token)
      return unless plan

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
