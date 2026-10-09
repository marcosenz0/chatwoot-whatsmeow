class Api::V1::Accounts::MarcosxAi::ConversationDraftsController < Api::V1::Accounts::MarcosxAi::BaseController
  rescue_from CustomExceptions::MarcosxAi do |error|
    render json: { error: error.message }, status: :unprocessable_entity
  end

  def create
    conversation = Current.account.conversations.find_by!(display_id: params[:conversation_id])
    authorize conversation, :show?
    draft = params.require(:draft).permit(:action, :content, :instruction)
    render json: MarcosxAi::ComposerDraftService.new(conversation: conversation, action: draft[:action],
                                                     content: draft[:content], instruction: draft[:instruction]).perform
  end
end
