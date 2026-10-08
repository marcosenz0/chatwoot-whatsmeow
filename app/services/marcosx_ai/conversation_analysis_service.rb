class MarcosxAi::ConversationAnalysisService
  SCHEMA = MarcosxAi::ReplyPlan::SCHEMA.merge(
    properties: MarcosxAi::ReplyPlan::SCHEMA[:properties].merge(summary: { type: 'string' }, next_step: { type: 'string' }),
    required: [*MarcosxAi::ReplyPlan::SCHEMA[:required], 'summary', 'next_step']
  ).freeze

  def initialize(state:)
    @state = state
    @conversation = state.conversation
    @assistant = state.assistant
  end

  def start!
    raise CustomExceptions::MarcosxAi, I18n.t('marcosx_ai.errors.credential_missing') unless @assistant.available?

    latest = history.reorder(:id).last
    raise CustomExceptions::MarcosxAi, I18n.t('marcosx_ai.errors.empty_history') unless latest

    token = SecureRandom.uuid
    @state.with_lock do
      @state.pause_by_agent!(reason: 'draft_review')
      analysis = {
        'id' => token, 'status' => 'processing', 'trigger_message_id' => latest.id, 'messages_count' => history.count,
        'assistant_version' => @assistant.updated_at.iso8601(6), 'created_at' => Time.current.iso8601
      }
      @state.update!(metadata: @state.metadata.merge('analysis' => analysis))
    end
    MarcosxAi::ConversationAnalysisJob.perform_later(@state.id, token)
    report
  end

  def perform(token)
    return invalidate(token) unless current?(token)

    analysis = @state.metadata.fetch('analysis')
    client = MarcosxAi::ProviderClient.new(account: @state.account, provider: @assistant.provider, model: @assistant.model,
                                           temperature: @assistant.temperature, reasoning_effort: @assistant.reasoning_effort)
    context = MarcosxAi::ConversationContext.new(
      conversation: @conversation, assistant: @assistant, state: @state, client: client,
      trigger_message: history.find(analysis.fetch('trigger_message_id')), token: token,
      persist_memory: false, valid_run: -> { current?(token) }
    ).messages
    return invalidate(token) unless current?(token)

    prompts = MarcosxAi::PromptBuilder.messages(
      assistant: @assistant, context: { contact: @conversation.contact.name, inbox: @conversation.inbox.name, now: Time.current.iso8601 },
      reactions: @assistant.feature_enabled?(:allow_reactions) && @state.inbox.channel_type == 'Channel::Whatsmeow', proactive: true
    )
    prompts << {
      role: 'system', content: <<~PROMPT
        Esta é uma análise interna solicitada pelo atendente. Nenhuma mensagem será enviada automaticamente.
        Em summary, resuma toda a conversa fornecida: fatos confirmados, preferências, pendências e o último contexto.
        Em next_step, explique brevemente a melhor próxima ação ao atendente. Prepare em messages uma resposta ao contato,
        seguindo as instruções do agente. Use o resumo anterior como contexto factual, sem inventar informações.
      PROMPT
    }
    result = JSON.parse(client.chat(messages: [*prompts, *context], schema: SCHEMA))
    plan = MarcosxAi::ReplyPlan.parse(result.to_json, assistant: @assistant)
    unless result['summary'].is_a?(String) && result['next_step'].is_a?(String)
      raise CustomExceptions::MarcosxAi, I18n.t('marcosx_ai.errors.invalid_response')
    end

    @state.with_lock do
      return invalidate(token) unless current?(token)

      @state.update!(metadata: @state.metadata.merge('analysis' => analysis.merge(
        'status' => 'ready', 'summary' => result['summary'], 'next_step' => result['next_step'], 'plan' => plan
      )))
    end
    MarcosxAi::Log.create!(account: @state.account, assistant: @assistant, conversation: @conversation, event: 'analysis_ready',
                           response: { model: @assistant.model, messages_count: analysis['messages_count'], parts: plan['messages'].size })
  rescue StandardError => e
    @state.with_lock do
      return unless @state.metadata.dig('analysis', 'id') == token

      @state.update!(metadata: @state.metadata.merge('analysis' => @state.metadata['analysis'].merge('status' => 'failed')))
    end
    Rails.logger.warn("MarcoXIA analysis failed (state #{@state.id}): #{e.class.name}")
  end

  def report
    analysis = @state.reload.metadata['analysis']
    return { status: 'idle' } unless analysis

    data = analysis.slice('id', 'status', 'created_at', 'messages_count', 'summary', 'next_step', 'plan')
    data['status'] = 'outdated' if data['status'].in?(%w[processing ready]) && !snapshot_current?(analysis)
    data
  end

  def send!(token:, messages:)
    run_token = SecureRandom.uuid
    @state.with_lock do
      analysis = @state.metadata['analysis']
      unless analysis && analysis['id'] == token && analysis['status'] == 'ready' && snapshot_current?(analysis)
        raise CustomExceptions::MarcosxAi, I18n.t('marcosx_ai.errors.analysis_outdated')
      end
      unless @assistant.available? && @assistant.accepts_conversation?(@conversation) &&
             !@conversation.resolved? && !@conversation.snoozed?
        raise CustomExceptions::MarcosxAi, I18n.t('marcosx_ai.errors.conversation_unavailable')
      end

      plan = MarcosxAi::ReplyPlan.parse(analysis.fetch('plan').merge('messages' => messages).to_json, assistant: @assistant)
      if plan['messages'].empty? && plan['reaction'].blank? && !plan['handoff']
        raise CustomExceptions::MarcosxAi, I18n.t('marcosx_ai.errors.empty_response')
      end

      @state.pause_by_agent!(reason: 'draft_review')
      @state.update!(metadata: @state.metadata.merge(
        'run_token' => run_token, 'trigger_message_id' => analysis['trigger_message_id'],
        'assistant_version' => @assistant.updated_at.iso8601(6), 'approved_draft' => true, 'processing' => true,
        'pending_response' => plan.merge('next_part' => 0), 'analysis' => analysis.merge('status' => 'sent')
      ))
    end
    MarcosxAi::DeliveryJob.perform_later(@conversation.id, run_token, 0)
  end

  private

  def history
    @conversation.messages.where(message_type: [:incoming, :outgoing], private: false)
                 .where.not(content_type: Message.content_types[:voice_call])
  end

  def snapshot_current?(analysis)
    @assistant && @state.assistant_id == @assistant.id &&
      analysis['assistant_version'] == @assistant.reload.updated_at.iso8601(6) && history.maximum(:id) == analysis['trigger_message_id']
  end

  def current?(token)
    analysis = @state.reload.metadata['analysis']
    analysis && analysis['id'] == token && analysis['status'] == 'processing' && snapshot_current?(analysis)
  end

  def invalidate(token)
    @state.with_lock do
      analysis = @state.metadata['analysis']
      return unless analysis && analysis['id'] == token

      @state.update!(metadata: @state.metadata.merge('analysis' => analysis.merge('status' => 'outdated')))
    end
  end
end
