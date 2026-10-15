class MarcosxAi::ComposerDraftService
  TASKS = {
    'reply_suggestion' => 'Suggest the next reply to the contact, following the configured system prompt and conversation context.',
    'reply_review' => 'Prepare the next reply for the operator to review before sending, honoring the current voice preference.',
    'voice_reply' => 'Prepare a short spoken reply to the latest contact request. ' \
                     'Return the complete spoken text in messages, without URLs, emoji or Markdown.',
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

  SCHEMA = MarcosxAi::ReplyPlan::SCHEMA.merge(
    properties: MarcosxAi::ReplyPlan::SCHEMA[:properties].merge(
      messages: { type: 'array', minItems: 1, items: { type: 'string', minLength: 1 } }
    )
  ).freeze

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

    if !%w[reply_suggestion reply_review voice_reply summarize].include?(@action) && (!@content.is_a?(String) || @content.blank?)
      raise CustomExceptions::MarcosxAi, I18n.t('marcosx_ai.errors.invalid_response')
    end

    if @action == 'voice_reply' && (!assistant.voice_ready? || !MarcosxAi::VoiceClient::CHANNELS.include?(@conversation.inbox.channel_type))
      raise CustomExceptions::MarcosxAi, I18n.t('marcosx_ai.errors.voice_unavailable')
    end

    trigger = MarcosxAi::ConversationContext.public_history(@conversation).order(:created_at, :id).last
    raise CustomExceptions::MarcosxAi, I18n.t('marcosx_ai.errors.empty_response') unless trigger

    version = assistant.updated_at
    state = @conversation.marcosx_ai_conversation_state || MarcosxAi::ConversationState.new(metadata: {})
    client = MarcosxAi::ProviderClient.new(account: @conversation.account, provider: assistant.provider, model: assistant.model,
                                           temperature: assistant.temperature, reasoning_effort: assistant.reasoning_effort)
    history = MarcosxAi::ConversationContext.new(conversation: @conversation, assistant: assistant, state: state, client: client,
                                                 trigger_message: trigger, token: nil, persist_memory: false, valid_run: -> { true }).messages
    prompts = MarcosxAi::PromptBuilder.messages(assistant: assistant, conversation: @conversation,
                                                context: MarcosxAi::PromptBuilder.context_for(@conversation, assistant: assistant),
                                                reactions: false, proactive: true)
    task = "Operator draft only. Do not send messages or execute actions. #{TASKS.fetch(@action)} " \
           'Use the conversation language. Return a nonempty draft in messages, with reaction null, handoff false, ' \
           'resource_ids empty and pix_key_id null. ' \
           'This draft cannot send files or Pix cards. Do not write a Pix key or claim a Pix card was sent. ' \
           'Do not say a file has been sent or attached. ' \
           'The operator explicitly requested a draft, even if the latest history message already received a reply. Do not choose silence.'
    if @action == 'voice_reply'
      task += ' The operator will review and generate the audio. ' \
              "Keep the spoken draft within #{assistant.resolved_config.dig(:voice, :max_characters)} characters."
    end
    if @action == 'reply_review'
      task += ' For a voice preference, also return the complete spoken reply in voice_text. The operator must listen before sending.'
    end
    messages = [*prompts, { role: 'system', content: task }, *MarcosxAi::PromptBuilder.focused_history(history)]
    if @content.present?
      draft = { draft_to_edit: @content.to_s.truncate(15_000), operator_request: @instruction.to_s.truncate(2000) }
      messages << { role: 'user', content: draft.to_json }
    end
    voice_context = MarcosxAi::VoicePolicy.context(assistant: assistant, conversation: @conversation) if @action == 'reply_review'
    plan = MarcosxAi::ReplyPlan.parse(client.chat(messages: messages, schema: SCHEMA), assistant: assistant, conversation: @conversation,
                                                                                       voice_context: voice_context)
    raise CustomExceptions::MarcosxAi, I18n.t('marcosx_ai.errors.empty_response') if plan['messages'].empty?

    latest = MarcosxAi::ConversationContext.public_history(@conversation).order(:created_at, :id).last
    if assistant.reload.updated_at != version || latest&.id != trigger.id || @conversation.reload.marcosx_ai_assistant&.id != assistant.id
      raise CustomExceptions::MarcosxAi, I18n.t('marcosx_ai.errors.analysis_outdated')
    end

    result = { content: plan['messages'].join("\n\n"), assistant_name: assistant.name }
    result[:voice_text] = plan['voice_text'] if @action == 'reply_review'
    result[:max_characters] = assistant.resolved_config.dig(:voice, :max_characters)
    result
  end
end
