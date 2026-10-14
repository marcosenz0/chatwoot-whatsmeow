class MarcosxAi::ReviewedReplyService
  PURPOSE = 'marcoxia-reviewed-reply'.freeze

  def initialize(conversation:)
    @conversation = conversation
    @assistant = conversation.marcosx_ai_assistant
  end

  def snapshot
    raise CustomExceptions::MarcosxAi, I18n.t('marcosx_ai.errors.invalid_assistant') unless @assistant

    @assistant.reload

    { 'conversation_id' => @conversation.id, 'assistant_id' => @assistant.id,
      'assistant_version' => @assistant.updated_at.iso8601(6),
      'message_id' => MarcosxAi::ConversationContext.public_history(@conversation).maximum(:id) }
  end

  def token(snapshot:, audio: nil, content: nil)
    ensure_current!(snapshot)
    Rails.application.message_verifier(PURPOSE).generate(
      snapshot.merge('audio_digest' => audio && Digest::SHA256.hexdigest(audio), 'spoken_text' => audio && content),
      purpose: PURPOSE, expires_in: 30.minutes
    )
  end

  def send!(token:, content:, audio: nil)
    executed_by = Current.executed_by
    claims = Rails.application.message_verifier(PURPOSE).verified(token, purpose: PURPOSE) if token.is_a?(String)
    raise CustomExceptions::MarcosxAi, I18n.t('marcosx_ai.errors.analysis_outdated') unless claims
    raise CustomExceptions::MarcosxAi, I18n.t('marcosx_ai.errors.invalid_response') unless content.is_a?(String) && content.present?

    state = @conversation.marcosx_ai_conversation_state
    unless state
      ensure_current!(claims)
      state = MarcosxAi::ConversationState.for_conversation!(@conversation, assistant: @assistant)
    end
    receipt = Digest::SHA256.hexdigest(token)
    state.with_lock do
      previous = state.metadata['reviewed_reply']
      return @conversation.messages.find(previous.fetch('message_id')) if previous && previous['receipt'] == receipt

      ensure_current!(claims)
      unless @assistant.available? && @assistant.accepts_conversation?(@conversation) && !@conversation.resolved? && !@conversation.snoozed?
        raise CustomExceptions::MarcosxAi, I18n.t('marcosx_ai.errors.conversation_unavailable')
      end

      if audio && audio.size > MarcosxAi::VoiceClient::MAX_BYTES
        raise CustomExceptions::MarcosxAi, I18n.t('marcosx_ai.errors.invalid_response')
      end

      bytes = audio&.read
      if claims['audio_digest']
        unless bytes && audio.content_type == 'audio/mpeg' && Digest::SHA256.hexdigest(bytes) == claims['audio_digest'] &&
               content.strip == claims['spoken_text'] && @assistant.voice_ready? &&
               MarcosxAi::VoiceClient::CHANNELS.include?(@conversation.inbox.channel_type)
          raise CustomExceptions::MarcosxAi, I18n.t('marcosx_ai.errors.invalid_response')
        end
      elsif audio || content.length > 15_000
        raise CustomExceptions::MarcosxAi, I18n.t('marcosx_ai.errors.invalid_response')
      end
      Current.executed_by = @assistant
      message = @conversation.messages.new(
        account: @conversation.account, inbox: @conversation.inbox, sender: @assistant, message_type: :outgoing,
        content: bytes ? nil : content.strip,
        additional_attributes: { marcosx_ai: true, assistant_name: @assistant.name, trigger_message_id: claims['message_id'], reviewed_reply: true }
      )
      if bytes
        message.content_attributes = { whatsmeow_recorded_audio: true, marcosx_ai_voice_transcript: content.strip }
        attachment = message.attachments.build(account: @conversation.account, file_type: :audio,
                                               meta: { is_voice_message: true, transcribed_text: content.strip })
        attachment.file.attach(io: StringIO.new(bytes), filename: 'agent-voice.mp3', content_type: 'audio/mpeg')
      end
      message.save!
      metadata = state.metadata.except('pending_response', 'pending_since_message_id', 'approved_draft')
      state.update!(last_ai_message_id: message.id, metadata: metadata.merge(
        'run_token' => SecureRandom.uuid, 'processing' => false,
        'last_processed_trigger_id' => claims['message_id'], 'reviewed_reply' => { 'receipt' => receipt, 'message_id' => message.id }
      ))
      MarcosxAi::Log.create!(account: state.account, assistant: @assistant, conversation: @conversation, event: 'reviewed_reply_sent',
                             response: { audio: bytes.present?, message_id: message.id })
      message
    end
  ensure
    Current.executed_by = executed_by
  end

  private

  def ensure_current!(claims)
    unless claims.slice('conversation_id', 'assistant_id', 'assistant_version', 'message_id') == snapshot &&
           @conversation.reload.marcosx_ai_assistant&.id == @assistant.id
      raise CustomExceptions::MarcosxAi, I18n.t('marcosx_ai.errors.analysis_outdated')
    end
  end
end
