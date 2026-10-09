class Api::V1::Accounts::MarcosxAi::ConversationDraftsController < Api::V1::Accounts::MarcosxAi::BaseController
  rescue_from CustomExceptions::MarcosxAi do |error|
    render json: { error: error.message }, status: :unprocessable_entity
  end

  def create
    conversation = Current.account.conversations.find_by!(display_id: params[:conversation_id])
    authorize conversation, :show?
    draft = params.require(:draft).permit(:action, :content, :instruction)
    render json: MarcosxAi::ComposerDraftService.new(conversation: conversation, **draft.to_h.symbolize_keys).perform
  end
end
