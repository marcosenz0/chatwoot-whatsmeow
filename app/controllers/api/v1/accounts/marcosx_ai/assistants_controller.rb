class Api::V1::Accounts::MarcosxAi::AssistantsController < Api::V1::Accounts::MarcosxAi::BaseController
  before_action :ensure_admin!, except: [:index, :show, :playground]
  before_action :set_assistant, only: [:show, :update, :destroy, :playground]

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

  def playground
    blobs = []
    message = playground_params[:message]
    return render json: { error: 'A message is required' }, status: :unprocessable_entity if message.blank?

    client = MarcosxAi::ProviderClient.new(account: Current.account, provider: @assistant.provider, model: @assistant.model,
                                           temperature: @assistant.temperature, reasoning_effort: @assistant.reasoning_effort)
    prompts = MarcosxAi::PromptBuilder.messages(assistant: @assistant, reactions: @assistant.feature_enabled?(:allow_reactions))
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
    render json: { response: plan['messages'].join("\n\n"), plan: plan, usage: client.usage,
                   user_context: parts.map { |part| part[:text] }.join("\n") }
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  ensure
    blobs&.each(&:purge)
  end

  private

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
        :human_pause_minutes,
        :auto_response_enabled,
        :fallback_message,
        :handoff_message,
        :split_messages, :max_message_parts, :message_interval_seconds, :allow_reactions,
        :process_images, :process_audio, :process_files, :process_video, :respond_to_groups, :auto_start
      ],
      response_guidelines: [],
      guardrails: []
    )
    permitted[:config] = (@assistant&.resolved_config || MarcosxAi::Assistant::DEFAULT_CONFIG).merge(permitted[:config] || {})
    permitted
  end

  def playground_params
    params.require(:assistant).permit(:message, history: [:role, :content])
  end

  def serialize(assistant)
    {
      id: assistant.id,
      name: assistant.name,
      description: assistant.description,
      instructions: assistant.instructions,
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
