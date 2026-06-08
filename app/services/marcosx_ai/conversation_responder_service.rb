class MarcosxAi::ConversationResponderService
  def initialize(conversation:, assistant:, trigger_message: nil)
    @conversation = conversation
    @assistant = assistant
    @trigger_message = trigger_message
    @state = MarcosxAi::ConversationState.for_conversation!(conversation, assistant: assistant)
  end

  def perform
    return unless @assistant.auto_response_enabled?
    return unless @state.active_for_ai?

    response = generate_response
    message = create_ai_message(response)
    @state.update!(assistant: @assistant, status: 'active', last_ai_message_id: message.id)
    log_event('response_created', response: { message_id: message.id, model: @assistant.model, provider: @assistant.provider })
    message
  rescue StandardError => e
    handle_error(e)
  end

  private

  def generate_response
    response = MarcosxAi::ProviderClient.new(
      account: @conversation.account,
      provider: @assistant.provider,
      model: @assistant.model,
      temperature: @assistant.temperature
    ).chat(messages: messages_for_llm)

    response.presence || @assistant.fallback_message
  end

  def messages_for_llm
    [
      { role: 'system', content: system_prompt },
      *conversation_history
    ]
  end

  def system_prompt
    [
      "Voce e a MarcosX IA, uma assistente de atendimento dentro do Chatwoot.",
      "Responda em portugues do Brasil, com clareza, naturalidade e foco em resolver o atendimento.",
      "Se precisar de humano, responda com uma frase curta informando que vai transferir.",
      @assistant.instructions.presence,
      "Nome do contato: #{@conversation.contact&.name}",
      "Telefone do contato: #{@conversation.contact&.phone_number}",
      "Caixa de entrada: #{@conversation.inbox&.name}"
    ].compact_blank.join("\n")
  end

  def conversation_history
    @conversation.messages
                 .where(message_type: [:incoming, :outgoing])
                 .where(private: false)
                 .last(@assistant.history_limit)
                 .filter_map do |message|
      content = message.processed_message_content.presence || message.content
      next if content.blank?

      { role: role_for(message), content: content.to_s }
    end
  end

  def role_for(message)
    message.incoming? ? 'user' : 'assistant'
  end

  def create_ai_message(content)
    Current.executed_by = @assistant
    @conversation.messages.create!(
      message_type: :outgoing,
      account_id: @conversation.account_id,
      inbox_id: @conversation.inbox_id,
      sender: @assistant,
      content: content,
      additional_attributes: {
        marcosx_ai: true,
        provider: @assistant.provider,
        model: @assistant.model,
        trigger_message_id: @trigger_message&.id
      }
    )
  ensure
    Current.executed_by = nil
  end

  def handle_error(error)
    fallback_message = create_fallback_message
    metadata = @state.metadata.merge('last_error' => error.message)
    metadata['last_fallback_message_id'] = fallback_message.id if fallback_message.present?
    @state.update!(assistant: @assistant, status: 'error', last_ai_message_id: fallback_message&.id, metadata: metadata)
    log_event('response_failed', status: 'error', response: { fallback_message_id: fallback_message&.id }, error: error.message)
    ChatwootExceptionTracker.new(error, account: @conversation.account).capture_exception
    nil
  end

  def create_fallback_message
    return if @assistant.fallback_message.blank?

    create_ai_message(@assistant.fallback_message)
  rescue StandardError => e
    log_event('fallback_failed', status: 'error', error: e.message)
    ChatwootExceptionTracker.new(e, account: @conversation.account).capture_exception
    nil
  end

  def log_event(event, status: 'ok', request: {}, response: {}, error: nil)
    MarcosxAi::Log.create!(
      account: @conversation.account,
      assistant: @assistant,
      conversation: @conversation,
      event: event,
      status: status,
      request: request,
      response: response,
      error: error
    )
  end
end
