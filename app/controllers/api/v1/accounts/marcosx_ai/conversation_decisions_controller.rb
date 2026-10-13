class Api::V1::Accounts::MarcosxAi::ConversationDecisionsController < Api::V1::Accounts::MarcosxAi::BaseController
  before_action :ensure_admin!

  def show
    conversation = Current.account.conversations.find_by!(display_id: params[:conversation_id])
    authorize conversation, :show?
    id = params[:message_id]
    unless id.is_a?(String) && id.match?(/\A[1-9]\d*\z/)
      return render json: { error: I18n.t('marcosx_ai.errors.invalid_response') }, status: :unprocessable_entity
    end

    message = conversation.messages.find(id)
    unless message.private? && message.additional_attributes['marcosx_ai'] == true && message.sender.is_a?(MarcosxAi::Assistant)
      return render json: { error: I18n.t('marcosx_ai.errors.invalid_response') }, status: :unprocessable_entity
    end

    render json: MarcosxAi::DecisionTrace.report(message: message)
  end
end
