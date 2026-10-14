class MarcosxAi::DeliveryJob < ApplicationJob
  # Keep delayed message parts in the same durable queue as response generation.
  self.queue_adapter = :sidekiq unless Rails.env.test?
  queue_as :default
  discard_on ActiveRecord::RecordNotFound

  def perform(conversation_id, token, part_index)
    @state = MarcosxAi::ConversationState.find_by!(conversation_id: conversation_id)
    return unless @state.current_run?(token)

    pending = @state.metadata['pending_response']
    return unless pending && pending['next_part'] == part_index

    prepare_audio(pending, token) if part_index.zero?
    @state.with_lock do
      return unless @state.current_run?(token)

      plan = @state.metadata['pending_response']
      return unless plan && plan['next_part'] == part_index

      if part_index.zero?
        if @audio
          plan['reaction'] = nil
          plan['messages'] = plan['messages'].select { |text|
            text.match?(%r{https?://|www\.}i)
          } unless @state.assistant.resolved_config.dig(:voice, :send_text)
        else
          plan = plan.merge('voice_text' => nil)
        end
        react(plan)
      end
      audio_count = plan['voice_text'].present? ? 1 : 0
      resources = Array(plan['resource_ids'])
      message = if part_index.zero? && @audio
                  create_audio_message(plan['voice_text'])
                elsif part_index - audio_count < plan['messages'].size
                  create_message(plan['messages'][part_index - audio_count])
                else
                  create_resource_message(resources[part_index - audio_count - plan['messages'].size])
                end
      @state.update!(last_ai_message_id: message.id) if message
      if part_index + 1 >= plan['messages'].size + audio_count + resources.size
        finish(plan)
      else
        @state.update!(metadata: @state.metadata.merge('pending_response' => plan.merge('next_part' => part_index + 1)))
        self.class.set(wait: @state.assistant.message_interval_seconds.seconds).perform_later(conversation_id, token, part_index + 1)
      end
    end
  rescue StandardError => e
    MarcosxAi::FailureHandler.perform(state: @state, token: token, error: e) if @state
  end

  private

  def prepare_audio(plan, token)
    return if plan['voice_text'].blank? || plan['handoff']
    return unless @state.assistant.voice_ready? && MarcosxAi::VoiceClient::CHANNELS.include?(@state.inbox.channel_type)

    @state.with_lock do
      return unless @state.current_run?(token)

      @state.update!(metadata: @state.metadata.merge('presence_media' => 'audio'))
    end
    MarcosxAi::TypingPresenceJob.perform_now(@state.conversation_id, token)
    @audio = MarcosxAi::VoiceClient.new(assistant: @state.assistant).synthesize(plan['voice_text'])
  rescue StandardError
    MarcosxAi::Log.create!(account: @state.account, assistant: @state.assistant, conversation: @state.conversation,
                           event: 'voice_failed', status: 'error', error: 'Voice synthesis failed; continuing with text.')
    @audio = nil
    @state.with_lock { @state.update!(metadata: @state.metadata.except('presence_media')) } if @state.current_run?(token)
  end

  def create_audio_message(transcript)
    executed_by = Current.executed_by
    Current.executed_by = @state.assistant
    message = @state.conversation.messages.new(
      message_type: :outgoing, account: @state.account, inbox: @state.inbox, sender: @state.assistant,
      content_attributes: { whatsmeow_recorded_audio: true, marcosx_ai_voice_transcript: transcript },
      additional_attributes: { marcosx_ai: true, assistant_name: @state.assistant.name,
                               trigger_message_id: @state.metadata['trigger_message_id'] }
    )
    attachment = message.attachments.build(account: @state.account, file_type: :audio, meta: { is_voice_message: true, transcribed_text: transcript })
    attachment.file.attach(io: StringIO.new(@audio), filename: 'agent-voice.mp3', content_type: 'audio/mpeg')
    message.save!
    message
  ensure
    Current.executed_by = executed_by
  end

  def react(plan)
    return unless @state.assistant.feature_enabled?(:allow_reactions) && @state.inbox.channel_type == 'Channel::Whatsmeow'
    return unless MarcosxAi::ReplyPlan::REACTIONS.include?(plan['reaction'])

    target = @state.conversation.messages.incoming.find_by(id: plan['reaction_message_id'])
    if target.blank? || target.source_id.blank? || target.content_attributes['deleted']
      raise CustomExceptions::MarcosxAi, I18n.t('marcosx_ai.errors.invalid_response') if plan['messages'].empty?

      return
    end

    Whatsmeow::ReactionService.new(message: target, emoji: plan['reaction'], actor: @state.assistant).perform
  end

  def create_message(content)
    executed_by = Current.executed_by
    Current.executed_by = @state.assistant
    @state.conversation.messages.create!(
      message_type: :outgoing, account: @state.account, inbox: @state.inbox, sender: @state.assistant, content: content,
      additional_attributes: { marcosx_ai: true, provider: @state.assistant.provider, model: @state.assistant.model,
                               assistant_name: @state.assistant.name,
                               trigger_message_id: @state.metadata['trigger_message_id'] }
    )
  ensure
    Current.executed_by = executed_by
  end

  def finish(plan)
    metadata = @state.metadata.except('pending_response', 'pending_since_message_id', 'approved_draft', 'pause_ack', 'call_event', 'presence_media')
    @state.update!(metadata: metadata.merge(
      'processing' => false, 'last_processed_trigger_id' => @state.metadata['trigger_message_id']
    ))
    if plan['handoff']
      if @state.automatic_handoff_enabled?
        @state.handoff!(reason: plan['handoff_reason']) unless @state.metadata['manual_activation'] == true || @state.status == 'awaiting_human'
        @state.conversation.bot_handoff! if @state.conversation.pending?
      end
      MarcosxAi::DecisionTrace.write_note(state: @state,
                                          content: I18n.t('marcosx_ai.handoff_note', name: @state.assistant.name, reason: plan['handoff_reason']))
    end
    MarcosxAi::Log.create!(account: @state.account, assistant: @state.assistant, conversation: @state.conversation,
                           event: plan['handoff'] ? 'handoff' : 'response_sent',
                           response: { parts: plan['messages'].size, audio: plan['voice_text'].present?,
                                       resources: Array(plan['resource_ids']).size, reaction: plan['reaction'] })
  end

  def create_resource_message(id)
    executed_by = Current.executed_by
    resource = @state.assistant.resources.available.find_by(id: id)
    return unless resource
    return create_message(resource.url) if resource.kind == 'link'

    Current.executed_by = @state.assistant
    message = @state.conversation.messages.new(
      message_type: :outgoing, account: @state.account, inbox: @state.inbox, sender: @state.assistant,
      additional_attributes: { marcosx_ai: true, assistant_name: @state.assistant.name,
                               marcosx_ai_resource_id: resource.id, trigger_message_id: @state.metadata['trigger_message_id'] }
    )
    message.attachments.build(account: @state.account, file_type: resource.kind).file.attach(resource.file.blob)
    message.save!
    message
  ensure
    Current.executed_by = executed_by
  end
end
