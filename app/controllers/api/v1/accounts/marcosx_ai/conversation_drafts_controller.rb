class Api::V1::Accounts::MarcosxAi::ConversationDraftsController < Api::V1::Accounts::MarcosxAi::BaseController
  rescue_from CustomExceptions::MarcosxAi do |error|
    render json: { error: error.message }, status: :unprocessable_entity
  end

  def create
    conversation = Current.account.conversations.find_by!(display_id: params[:conversation_id])
    authorize conversation, :show?
    draft = params.require(:draft).permit(:action, :content, :instruction)
    review = MarcosxAi::ReviewedReplyService.new(conversation: conversation)
    snapshot = review.snapshot
    result = MarcosxAi::ComposerDraftService.new(conversation: conversation, action: draft[:action],
                                                 content: draft[:content], instruction: draft[:instruction]).perform
    render json: result.merge(review_token: review.token(snapshot: snapshot),
                              auto_generate_audio: current_user.ui_settings['marcoxia_auto_generate_audio'] == true)
  end

  def voice_preference
    conversation = Current.account.conversations.find_by!(display_id: params[:conversation_id])
    authorize conversation, :show?
    enabled = params.require(:draft).permit(:auto_generate_audio)[:auto_generate_audio]
    unless [true, false].include?(enabled)
      return render json: { error: I18n.t('marcosx_ai.errors.invalid_response') }, status: :unprocessable_entity
    end

    current_user.with_lock do
      current_user.update!(ui_settings: current_user.ui_settings.merge('marcoxia_auto_generate_audio' => enabled))
    end
    render json: { auto_generate_audio: enabled }
  end

  def voice
    conversation = Current.account.conversations.find_by!(display_id: params[:conversation_id])
    authorize conversation, :show?
    assistant = conversation.marcosx_ai_assistant
    unless assistant&.voice_ready? && MarcosxAi::VoiceClient::CHANNELS.include?(conversation.inbox.channel_type)
      return render json: { error: I18n.t('marcosx_ai.errors.voice_unavailable') }, status: :unprocessable_entity
    end

    review = MarcosxAi::ReviewedReplyService.new(conversation: conversation)
    snapshot = review.snapshot
    content = params.require(:draft).permit(:content)[:content]
    audio = MarcosxAi::VoiceClient.new(assistant: assistant).synthesize(content)
    response.set_header('X-Marcoxia-Review-Token', review.token(snapshot: snapshot, audio: audio, content: content.strip))
    send_data audio, type: 'audio/mpeg', disposition: 'inline', filename: 'agent-voice.mp3'
  rescue MarcosxAi::VoiceClient::Error => error
    render json: { error: error.message }, status: :unprocessable_entity
  end

  def send_reply
    conversation = Current.account.conversations.find_by!(display_id: params[:conversation_id])
    authorize conversation, :show?
    draft = params.require(:draft).permit(:review_token, :content, :audio)
    if draft[:audio] && !draft[:audio].is_a?(ActionDispatch::Http::UploadedFile)
      return render json: { error: I18n.t('marcosx_ai.errors.invalid_response') }, status: :unprocessable_entity
    end

    message = MarcosxAi::ReviewedReplyService.new(conversation: conversation).send!(
      token: draft[:review_token], content: draft[:content], audio: draft[:audio]
    )
    render json: { message_id: message.id }
  end
end
