class Api::V1::Accounts::MarcosxAi::ConversationAnalysesController < Api::V1::Accounts::MarcosxAi::BaseController
  before_action :set_conversation
  rescue_from CustomExceptions::MarcosxAi do |error|
    render json: { error: error.message }, status: :unprocessable_entity
  end

  def show
    state = MarcosxAi::ConversationState.find_by(conversation: @conversation)
    render json: {
      analysis: state ? MarcosxAi::ConversationAnalysisService.new(state: state).report : { status: 'idle' },
      context: { total_messages_count: MarcosxAi::ConversationContext.public_history(@conversation).count,
                 messages_limit: state&.metadata&.fetch('context_messages_limit', nil) }
    }
  end

  def create
    id = analysis_params[:assistant_id]
    unless id.is_a?(Integer) && id.positive?
      return render json: { error: I18n.t('marcosx_ai.errors.invalid_assistant') }, status: :unprocessable_entity
    end

    assistant = Current.account.marcosx_ai_assistants.find(id)
    limit = analysis_params[:messages_limit]
    unless limit.nil? || (limit.is_a?(Integer) && limit.positive?)
      return render json: { error: I18n.t('marcosx_ai.errors.invalid_response') }, status: :unprocessable_entity
    end

    state = MarcosxAi::ConversationState.find_by(conversation: @conversation, assistant: assistant)
    state ||= MarcosxAi::ConversationState.choose_for_conversation!(@conversation, assistant: assistant)
    render json: { analysis: MarcosxAi::ConversationAnalysisService.new(state: state).start!(messages_limit: limit) }, status: :accepted
  end

  def send_reply
    unless analysis_params[:id].is_a?(String) && analysis_params[:messages].is_a?(Array) &&
           analysis_params[:messages].all? { |part| part.is_a?(String) }
      return render json: { error: I18n.t('marcosx_ai.errors.invalid_response') }, status: :unprocessable_entity
    end

    state = MarcosxAi::ConversationState.find_by!(conversation: @conversation)
    MarcosxAi::ConversationAnalysisService.new(state: state).send!(token: analysis_params[:id], messages: analysis_params[:messages])
    render json: { state: state.reload.public_data }, status: :accepted
  end

  private

  def set_conversation
    @conversation = Current.account.conversations.find_by!(display_id: params[:conversation_id])
    authorize @conversation, :show?
  end

  def analysis_params
    params.require(:analysis).permit(:assistant_id, :id, :messages_limit, messages: [])
  end
end
