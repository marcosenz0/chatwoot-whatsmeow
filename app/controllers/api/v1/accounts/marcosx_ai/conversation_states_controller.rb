class Api::V1::Accounts::MarcosxAi::ConversationStatesController < Api::V1::Accounts::MarcosxAi::BaseController
  before_action :set_conversation
  before_action :set_state

  def show
    return render json: { state: inactive_state } if @state.blank?

    render json: { state: serialize(@state) }
  end

  def update
    if @state.blank?
      return render json: { error: 'MarcosX IA is not enabled for this conversation' }, status: :unprocessable_entity
    end

    case state_params[:action]
    when 'pause'
      @state.pause_by_agent!(minutes: pause_minutes, reason: state_params[:reason])
    when 'resume'
      @state.resume!
    when 'handoff'
      @state.handoff!(reason: state_params[:reason])
      @conversation.bot_handoff! if @conversation.pending?
    else
      return render json: { error: 'Invalid action' }, status: :unprocessable_entity
    end

    render json: { state: serialize(@state) }
  end

  private

  def set_conversation
    @conversation = Current.account.conversations.find_by!(display_id: params[:conversation_id])
  end

  def set_state
    assistant = @conversation.inbox.marcosx_ai_assistant
    @state = MarcosxAi::ConversationState.find_by(conversation: @conversation)
    return if @state.blank? && assistant.blank?

    @state = MarcosxAi::ConversationState.for_conversation!(@conversation, assistant: assistant)
  end

  def state_params
    params.permit(:action, :minutes, :reason)
  end

  def pause_minutes
    minutes = state_params[:minutes].presence
    minutes.to_i.positive? ? minutes.to_i : 60
  end

  def serialize(state)
    {
      id: state.id,
      status: state.status,
      paused_until: state.paused_until,
      assistant_id: state.assistant_id,
      metadata: state.metadata,
      updated_at: state.updated_at
    }
  end

  def inactive_state
    {
      id: nil,
      status: 'inactive',
      paused_until: nil,
      assistant_id: nil,
      metadata: {},
      updated_at: nil
    }
  end
end
