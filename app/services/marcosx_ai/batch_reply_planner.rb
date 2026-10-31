class MarcosxAi::BatchReplyPlanner
  def self.perform(item)
    assistant = item.reply_batch.assistant
    conversation = item.conversation
    state = conversation.marcosx_ai_conversation_state&.dup || MarcosxAi::ConversationState.new(metadata: {})
    state.metadata = state.metadata.merge('pending_since_message_id' => item.trigger_message_id)
    client = MarcosxAi::ProviderClient.new(account: assistant.account, provider: assistant.provider, model: assistant.model,
                                           temperature: assistant.temperature, reasoning_effort: assistant.reasoning_effort,
                                           assistant: assistant, conversation: conversation, purpose: 'batch_reply')
    history = MarcosxAi::ConversationContext.new(conversation: conversation, assistant: assistant, state: state, client: client,
                                                 trigger_message: conversation.messages.find(item.trigger_message_id), token: nil,
                                                 persist_memory: false, valid_run: -> { item.reply_batch.reload.status != 'cancelled' }).messages
    runtime = MarcosxAi::PromptBuilder.context_for(conversation, assistant: assistant)
    prompts = MarcosxAi::PromptBuilder.messages(assistant: assistant, conversation: conversation, context: runtime, reactions: false, proactive: true)
    prompts << { role: 'developer', content: 'O operador selecionou este pedido ainda sem resposta. Prepare uma resposta ao pedido atual. ' \
                                             'Não execute ações agora. Reações devem ser null. Arquivos e Pix somente pelos catálogos autorizados.' }
    response = client.chat(messages: [*prompts, *MarcosxAi::PromptBuilder.focused_history(history, assistant: assistant)],
                           schema: MarcosxAi::ReplyPlan::SCHEMA)
    plan = MarcosxAi::ReplyPlan.parse(response, assistant: assistant, conversation: conversation,
                                                recent_messages: MarcosxAi::ReplyStyle.recent_text(history),
                                                voice_context: runtime[:voice], pix_available: runtime[:pix_available])
    if plan['recall_context']
      raise CustomExceptions::MarcosxAi, I18n.t('marcosx_ai.errors.batch_recall')
    end

    plan['reaction'] = nil
    plan['reaction_message_id'] = nil
    if plan['messages'].empty? && plan['voice_text'].blank? && Array(plan['resource_ids']).empty? && plan['pix_key_id'].nil?
      raise CustomExceptions::MarcosxAi, I18n.t('marcosx_ai.errors.empty_response')
    end

    plan
  end
end
