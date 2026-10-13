class Api::V1::Accounts::MarcosxAi::ConversationDecisionsController < Api::V1::Accounts::MarcosxAi::BaseController
  before_action :ensure_admin!

  def show
    conversation = Current.account.conversations.find_by!(display_id: params[:conversation_id])
    authorize conversation, :show?
    message = conversation.messages.find(params[:message_id])
    unless message.private? && message.additional_attributes['marcosx_ai'] == true && message.sender.is_a?(MarcosxAi::Assistant)
      return render json: { error: I18n.t('marcosx_ai.errors.invalid_response') }, status: :unprocessable_entity
    end

    render json: MarcosxAi::DecisionTrace.report(message: message)
  end
end
