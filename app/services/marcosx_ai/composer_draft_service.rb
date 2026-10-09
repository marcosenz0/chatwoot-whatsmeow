class MarcosxAi::ComposerDraftService
  TASKS = {
    'reply_suggestion' => 'Suggest the next reply to the contact, following the configured system prompt and conversation context.',
    'summarize' => 'Write a concise factual summary for the operator, preserving outstanding requests and relevant dates.',
    'improve' => 'Improve the supplied draft without adding unconfirmed facts.',
    'fix_spelling_grammar' => 'Correct spelling and grammar in the supplied draft while preserving its meaning.',
    'professional' => 'Rewrite the supplied draft in a professional tone.',
    'casual' => 'Rewrite the supplied draft in a casual tone.',
    'straightforward' => 'Rewrite the supplied draft directly and concisely.',
    'confident' => 'Rewrite the supplied draft confidently without exaggerating or adding claims.',
    'friendly' => 'Rewrite the supplied draft in a friendly tone.',
    'refine' => 'Adjust the supplied draft according to the operator request, without inventing facts.'
  }.freeze

  def initialize(conversation:, action:, content: nil, instruction: nil)
    @conversation = conversation
    @action = action
    @content = content
    @instruction = instruction
  end

  def perform
    raise CustomExceptions::MarcosxAi, I18n.t('marcosx_ai.errors.invalid_response') unless TASKS.key?(@action)

    assistant = @conversation.marcosx_ai_assistant
    raise CustomExceptions::MarcosxAi, I18n.t('marcosx_ai.errors.invalid_assistant') unless assistant
    raise CustomExceptions::MarcosxAi, I18n.t('marcosx_ai.errors.credential_missing') unless assistant.available?

    if !%w[reply_suggestion summarize].include?(@action) && (!@content.is_a?(String) || @content.blank?)
      raise CustomExceptions::MarcosxAi, I18n.t('marcosx_ai.errors.invalid_response')
    end

    trigger = MarcosxAi::ConversationContext.public_history(@conversation).order(:created_at, :id).last
    raise CustomExceptions::MarcosxAi, I18n.t('marcosx_ai.errors.empty_response') unless trigger

    version = assistant.updated_at
    state = @conversation.marcosx_ai_conversation_state || MarcosxAi::ConversationState.new(metadata: {})
    client = MarcosxAi::ProviderClient.new(account: @conversation.account, provider: assistant.provider, model: assistant.model,
                                           temperature: assistant.temperature, reasoning_effort: assistant.reasoning_effort)
    history = MarcosxAi::ConversationContext.new(conversation: @conversation, assistant: assistant, state: state, client: client,
                                                 trigger_message: trigger, token: nil, persist_memory: false, valid_run: -> { true }).messages
    prompts = MarcosxAi::PromptBuilder.messages(assistant: assistant,
                                                context: MarcosxAi::PromptBuilder.context_for(@conversation, assistant: assistant),
                                                reactions: false, proactive: true)
    task = "Operator draft only. Do not send messages or execute actions. #{TASKS.fetch(@action)} " \
           'Use the conversation language. Return the draft in messages, with reaction null and handoff false.'
    messages = [*prompts, { role: 'system', content: task }, *history]
    if @content.present?
      messages << { role: 'user', content: { draft_to_edit: @content.to_s.truncate(15_000),
                                           operator_request: @instruction.to_s.truncate(2000) }.to_json }
    end
    plan = MarcosxAi::ReplyPlan.parse(client.chat(messages: messages, schema: MarcosxAi::ReplyPlan::SCHEMA), assistant: assistant)
    raise CustomExceptions::MarcosxAi, I18n.t('marcosx_ai.errors.empty_response') if plan['messages'].empty?
    latest = MarcosxAi::ConversationContext.public_history(@conversation).order(:created_at, :id).last
    if assistant.reload.updated_at != version || latest&.id != trigger.id
      raise CustomExceptions::MarcosxAi, I18n.t('marcosx_ai.errors.analysis_outdated')
    end

    { content: plan['messages'].join("\n\n"), assistant_name: assistant.name }
  end
end
