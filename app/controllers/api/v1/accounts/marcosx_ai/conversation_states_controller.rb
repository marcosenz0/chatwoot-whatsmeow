class Api::V1::Accounts::MarcosxAi::ConversationStatesController < Api::V1::Accounts::MarcosxAi::BaseController
  before_action :set_conversation
  before_action :validate_action, only: :update
  before_action :set_state

  def show
    render json: {
      state: @state ? serialize(@state.reload) : inactive_state,
      assistants: Current.account.marcosx_ai_assistants.ordered.map do |assistant|
        { id: assistant.id, name: assistant.name, model: assistant.model, enabled: assistant.auto_response_enabled?, available: assistant.available? }
      end
    }
  end

  def update
    if @state.blank?
      return render json: { error: 'MarcosX IA is not enabled for this conversation' }, status: :unprocessable_entity
    end

    case state_params[:action]
    when 'pause'
      @state.with_lock { @state.pause_by_agent!(reason: state_params[:reason]) }
    when 'resume', 'reply_now'
      unless @state.assistant.available?
        return render json: { error: I18n.t('marcosx_ai.errors.credential_missing') }, status: :unprocessable_entity
      end

      return render json: { error: I18n.t('marcosx_ai.errors.conversation_unavailable') },
                    status: :unprocessable_entity if !@state.assistant.accepts_conversation?(@conversation) ||
                                                    @conversation.resolved? || @conversation.snoozed?

      @state.with_lock { @state.resume!(manual: true) }
      if state_params[:action] == 'reply_now'
        latest = @conversation.messages.where(message_type: [:incoming, :outgoing], private: false).order(:created_at, :id).last
        MarcosxAi::ResponseScheduler.perform(message: latest, manual: true) if latest
      end
    when 'handoff'
      @state.with_lock { @state.handoff!(reason: state_params[:reason]) }
      @conversation.bot_handoff! if @conversation.pending?
    when 'select'
      @state.with_lock { @state.pause_by_agent!(reason: 'agent_selected') }
    else
      return render json: { error: 'Invalid action' }, status: :unprocessable_entity
    end

    render json: { state: serialize(@state.reload) }
  end

  private

  def set_conversation
    @conversation = Current.account.conversations.find_by!(display_id: params[:conversation_id])
    authorize @conversation, :show?
  end

  def set_state
    if action_name == 'update' && state_params[:assistant_id].present?
      assistant = Current.account.marcosx_ai_assistants.find(state_params[:assistant_id])
      return @state = MarcosxAi::ConversationState.choose_for_conversation!(@conversation, assistant: assistant)
    end

    assistant = @conversation.marcosx_ai_assistant
    return @state = nil unless assistant

    @state = MarcosxAi::ConversationState.find_by(conversation: @conversation)
    return if @state.blank? && assistant.blank?

    @state = MarcosxAi::ConversationState.for_conversation!(@conversation, assistant: assistant)
  end

  def validate_action
    valid_action = %w[pause resume reply_now handoff select].include?(state_params[:action])
    id = state_params[:assistant_id]
    valid_id = id.nil? || (id.is_a?(Integer) && id.positive?)
    return if valid_action && valid_id

    render json: { error: I18n.t('marcosx_ai.errors.invalid_assistant') }, status: :unprocessable_entity
  end

  def state_params
    params.require(:state).permit(:action, :reason, :assistant_id)
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
