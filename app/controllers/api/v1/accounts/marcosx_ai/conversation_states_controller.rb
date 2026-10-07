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
      @state.with_lock { @state.pause_by_agent!(reason: state_params[:reason]) }
    when 'resume'
      return render json: { error: 'Enable the agent first' }, status: :unprocessable_entity unless @state.assistant.auto_response_enabled?

      @state.with_lock { @state.resume! }
      latest = @conversation.messages.where(message_type: [:incoming, :outgoing], private: false).order(:created_at, :id).last
      MarcosxAi::ResponseScheduler.perform(message: latest) if latest&.incoming?
    when 'reply_now'
      return render json: { error: 'Enable the agent first' }, status: :unprocessable_entity unless @state.assistant.auto_response_enabled?

      @state.with_lock { @state.resume! }
      latest = @conversation.messages.where(message_type: [:incoming, :outgoing], private: false).order(:created_at, :id).last
      MarcosxAi::ResponseScheduler.perform(message: latest, manual: true) if latest
    when 'handoff'
      @state.with_lock { @state.handoff!(reason: state_params[:reason]) }
      @conversation.bot_handoff! if @conversation.pending?
    else
      return render json: { error: 'Invalid action' }, status: :unprocessable_entity
    end

    render json: { state: serialize(@state) }
  end

  private

  def set_conversation
    @conversation = Current.account.conversations.find_by!(display_id: params[:conversation_id])
    authorize @conversation, :show?
  end

  def set_state
    assistant = @conversation.inbox.marcosx_ai_assistant
    return @state = nil unless assistant

    @state = MarcosxAi::ConversationState.find_by(conversation: @conversation)
    return if @state.blank? && assistant.blank?

    @state = MarcosxAi::ConversationState.for_conversation!(@conversation, assistant: assistant)
  end

  def state_params
    params.permit(:action, :minutes, :reason)
  end

  def serialize(state)
    state.public_data
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
