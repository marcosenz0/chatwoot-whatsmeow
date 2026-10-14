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

  def voice
    conversation = Current.account.conversations.find_by!(display_id: params[:conversation_id])
    authorize conversation, :show?
    assistant = conversation.marcosx_ai_assistant
    unless assistant&.voice_ready? && MarcosxAi::VoiceClient::CHANNELS.include?(conversation.inbox.channel_type)
      return render json: { error: I18n.t('marcosx_ai.errors.voice_unavailable') }, status: :unprocessable_entity
    end

    audio = MarcosxAi::VoiceClient.new(assistant: assistant).synthesize(params.require(:draft).permit(:content)[:content])
    send_data audio, type: 'audio/mpeg', disposition: 'inline', filename: 'agent-voice.mp3'
  rescue MarcosxAi::VoiceClient::Error => error
    render json: { error: error.message }, status: :unprocessable_entity
  end
end
