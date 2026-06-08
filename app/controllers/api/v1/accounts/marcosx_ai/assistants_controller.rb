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
    assistant = Current.account.marcosx_ai_assistants.create!(assistant_params)
    render json: { assistant: serialize(assistant) }
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def update
    @assistant.update!(assistant_params)
    render json: { assistant: serialize(@assistant) }
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def destroy
    @assistant.destroy!
    head :no_content
  end

  def playground
    message = playground_params[:message].presence || playground_params[:message_content]
    response = MarcosxAi::ProviderClient.new(
      account: Current.account,
      provider: @assistant.provider,
      model: @assistant.model,
      temperature: @assistant.temperature
    ).chat(messages: [
      { role: 'system', content: @assistant.instructions.presence || 'Voce e a MarcosX IA.' },
      { role: 'user', content: message.to_s }
    ])

    render json: { response: response }
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

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
        :response_delay_seconds,
        :history_limit,
        :human_pause_minutes,
        :auto_response_enabled,
        :fallback_message,
        :handoff_message
      ],
      response_guidelines: [],
      guardrails: []
    )
    permitted[:config] = MarcosxAi::Assistant::DEFAULT_CONFIG.merge(permitted[:config] || {})
    permitted
  end

  def playground_params
    params.require(:assistant).permit(:message, :message_content)
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
      created_at: assistant.created_at,
      updated_at: assistant.updated_at
    }
  end
end
