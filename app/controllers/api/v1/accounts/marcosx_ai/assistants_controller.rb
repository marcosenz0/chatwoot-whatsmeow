class Api::V1::Accounts::MarcosxAi::AssistantsController < Api::V1::Accounts::MarcosxAi::BaseController
  before_action :ensure_admin!, except: [:index, :show, :playground]
  before_action :set_assistant, only: [:show, :update, :destroy, :playground, :coverage, :prompt, :test_notification]

  def index
    render json: { assistants: Current.account.marcosx_ai_assistants.ordered.map { |assistant| serialize(assistant) } }
  end

  def show
    render json: { assistant: serialize(@assistant) }
  end

  def create
    assistant = nil
    ActiveRecord::Base.transaction do
      assistant = Current.account.marcosx_ai_assistants.create!(assistant_params)
      sync_inboxes(assistant)
    end
    render json: { assistant: serialize(assistant) }
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def update
    ActiveRecord::Base.transaction do
      @assistant.update!(assistant_params)
      sync_inboxes(@assistant)
    end
    render json: { assistant: serialize(@assistant) }
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def destroy
    @assistant.destroy!
    head :no_content
  end

  def notification_options
    render json: { users: Current.account.users.map { |user| { id: user.id, name: user.name } },
                   inboxes: Current.account.inboxes.where(channel_type: 'Channel::Whatsmeow').map { |inbox| { id: inbox.id, name: inbox.name } } }
  end

  def prompt
    messages = MarcosxAi::PromptBuilder.messages(assistant: @assistant, context: { runtime: 'contact, inbox, channel, timezone, now' },
                                                 reactions: @assistant.feature_enabled?(:allow_reactions))
    render json: { technical: messages.first[:content], editable: messages.last[:content] }
  end

  def test_notification
    id = params[:conversation_id]
    return render json: { error: 'Invalid conversation' }, status: :unprocessable_entity unless id.is_a?(Integer) && id.positive?

    conversation = Current.account.conversations.find_by!(display_id: id)
    authorize conversation, :show?
    configuration = @assistant.resolved_config[:notifications]
    if configuration[:user_ids].empty? && configuration[:whatsapp_numbers].empty?
      return render json: { error: 'Configure recipients first' }, status: :unprocessable_entity
    end

    alert = MarcosxAi::Alert.create!(account: Current.account, conversation: conversation, assistant: @assistant,
                                     rule_id: "test_#{SecureRandom.hex(8)}", name: I18n.t('marcosx_ai.notification_test'), action: 'notify',
                                     reason: I18n.t('marcosx_ai.notification_test'), configuration: configuration, status: 'resolved',
                                     resolved_by: Current.user, resolved_at: Time.current)
    MarcosxAi::AlertService.queue(alert)
    render json: { alert: alert.public_data }, status: :accepted
  end

  def coverage
    if @assistant.auto_response_enabled? && @assistant.feature_enabled?(:auto_start) && @assistant.inboxes.exists?
      return render json: { mode: 'automatic', conversations: [], total: nil }
    end

    states = attending_states
    page = params[:page].to_i.clamp(1, 100_000)
    conversations = states.includes(conversation: [:contact, :inbox]).order(updated_at: :desc).offset((page - 1) * 25).limit(25).map do |state|
      conversation = state.conversation
      {
        id: conversation.display_id, contact_id: conversation.contact_id, contact_name: conversation.contact.name,
        avatar_url: conversation.contact.avatar_url, inbox_name: conversation.inbox.name,
        processing: state.metadata['processing'] == true
      }
    end
    render json: { mode: 'individual', conversations: conversations, total: states.count, page: page }
  end

  def playground
    blobs = []
    message = playground_params[:message]
    return render json: { error: 'A message is required' }, status: :unprocessable_entity if message.blank?

    client = MarcosxAi::ProviderClient.new(account: Current.account, provider: @assistant.provider, model: @assistant.model,
                                           temperature: @assistant.temperature, reasoning_effort: @assistant.reasoning_effort)
    prompts = MarcosxAi::PromptBuilder.messages(assistant: @assistant, reactions: @assistant.feature_enabled?(:allow_reactions))
    if playground_params[:event] == 'missed_call'
      prompts << { role: 'developer', content: @assistant.resolved_config[:missed_call_instructions] }
      prompts << { role: 'user', content: 'Simulação: chamada recebida encerrada sem atendimento.' }
    end
    history = playground_params.fetch(:history, []).last(@assistant.history_limit).map { |item| { role: item[:role], content: item[:content] } }
    return render json: { error: 'Invalid history' }, status: :unprocessable_entity unless history.all? { |item|
      %w[user assistant].include?(item[:role])
    }

    files = params.fetch(:files, [])
    if files.size > 3 || files.any? { |file| file.size > MarcosxAi::MediaContext::MAX_BYTES }
      return render json: { error: I18n.t('marcosx_ai.errors.file_limit') }, status: :unprocessable_entity
    end

    parts = [{ type: 'input_text', text: message }]
    files.each do |file|
      type = file.content_type.split('/').first
      attachment = Attachment.new(file_type: %w[image audio video].include?(type) ? type : 'file')
      attachment.account = Current.account
      attachment.message = Message.new(content: message)
      blob = ActiveStorage::Blob.create_and_upload!(io: file.tempfile, filename: file.original_filename, content_type: file.content_type)
      blobs << blob
      attachment.file.attach(blob)
      parts << { type: 'input_text', text: MarcosxAi::MediaContext.new(attachment: attachment, assistant: @assistant, client: client).describe }
    end
    plan = MarcosxAi::ReplyPlan.parse(client.chat(messages: [*prompts, *history, { role: 'user', content: parts }],
                                                  schema: MarcosxAi::ReplyPlan::SCHEMA), assistant: @assistant)
    rules = @assistant.alert_rules.select { |rule| plan['alert_rule_ids'].include?(rule[:id]) }
    render json: { response: plan['messages'].join("\n\n"), plan: plan, usage: client.usage,
                   simulation: { alerts: rules.map { |rule| rule.slice(:id, :name, :action) },
                                 paused: rules.any? { |rule| rule[:action] == 'pause' } ||
                                         (plan['handoff'] && @assistant.feature_enabled?(:pause_on_handoff)),
                                 recall_requested: plan['recall_context'] },
                   user_context: parts.map { |part| part[:text] }.join("\n") }
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  ensure
    blobs&.each(&:purge)
  end

  private

  def attending_states
    states = @assistant.conversation_states.joins(conversation: :contact)
    states = states.where(status: 'active').or(states.where(status: 'paused_by_human').where('paused_until <= ?', Time.current))
    states = states.where(conversations: { status: [Conversation.statuses[:open], Conversation.statuses[:pending]] }, contacts: { blocked: false })
    states = states.where("metadata ->> 'conversation_override' = 'true'").or(states.where(inbox_id: @assistant.inboxes.select(:id)))
    states = states.where("metadata ->> 'manual_activation' = 'true'") unless @assistant.auto_response_enabled?
    states
  end

  def sync_inboxes(assistant)
    return unless params[:assistant].key?(:inbox_ids)

    ids = params.require(:assistant).permit(inbox_ids: [])[:inbox_ids]
    inboxes = Current.account.inboxes.where(id: ids)
    raise ActiveRecord::RecordNotFound unless inboxes.count == ids.uniq.size

    assistant.marcosx_ai_inboxes.where.not(inbox_id: ids).destroy_all
    existing = assistant.marcosx_ai_inboxes.pluck(:inbox_id)
    inboxes.each { |inbox| assistant.marcosx_ai_inboxes.create!(account: Current.account, inbox: inbox) unless existing.include?(inbox.id) }
  end

  def set_assistant
    @assistant = Current.account.marcosx_ai_assistants.find(params[:id])
  end

  def assistant_params
    permitted = params.require(:assistant).permit(
      :name,
      :description,
      :instructions,
      config: [
        :provider,
        :model,
        :temperature,
        :reasoning_effort,
        :response_delay_seconds,
        :history_limit,
        :timezone,
        :human_pause_minutes,
        :memory_mode, :editorial_instructions, :reply_to_missed_calls, :missed_call_instructions,
        :resume_mode, :resume_after_minutes, :pause_on_handoff, :pause_acknowledgement,
        :auto_response_enabled,
        :fallback_message,
        :handoff_message,
        :show_typing, :show_recording, :split_messages, :max_message_parts, :message_interval_seconds, :allow_reactions,
        :process_images, :process_audio, :process_files, :process_video, :respond_to_groups, :auto_start,
        { notifications: [:inbox_id, { user_ids: [], whatsapp_numbers: [] }],
          alert_rules: [:id, :name, :description, :message, :action, :inbox_id, { user_ids: [], whatsapp_numbers: [] }] }
      ],
      response_guidelines: [],
      guardrails: []
    )
    permitted[:config] = (@assistant&.resolved_config || MarcosxAi::Assistant::DEFAULT_CONFIG).merge(permitted[:config] || {})
    MarcosxAi::ConfigurationValidator.validate!(permitted[:config].to_h.with_indifferent_access, account: Current.account)
    permitted
  end

  def playground_params
    params.require(:assistant).permit(:message, :event, history: [:role, :content])
  end

  def serialize(assistant)
    {
      id: assistant.id,
      name: assistant.name,
      description: assistant.description,
      instructions: assistant.instructions,
      editorial_instructions: assistant.resolved_config[:editorial_instructions] || MarcosxAi::PromptBuilder::EDITORIAL_INSTRUCTIONS,
      config: assistant.resolved_config,
      response_guidelines: assistant.response_guidelines || [],
      guardrails: assistant.guardrails || [],
      inboxes_count: assistant.marcosx_ai_inboxes.count,
      inbox_ids: assistant.marcosx_ai_inboxes.pluck(:inbox_id),
      created_at: assistant.created_at,
      updated_at: assistant.updated_at
    }
  end
end
