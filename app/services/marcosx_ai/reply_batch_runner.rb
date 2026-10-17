class MarcosxAi::ReplyBatchRunner
  def initialize(batch)
    @batch = batch
    @assistant = batch.assistant
    @pending = MarcosxAi::PendingConversations.new(assistant: @assistant, user: batch.user)
  end

  def perform
    connection = ActiveRecord::Base.connection
    locked = connection.select_value("SELECT pg_try_advisory_lock(76016, #{@batch.id.to_i})")
    return unless locked

    run_next unless @batch.reload.status.in?(%w[cancelled completed ready])
  ensure
    connection.execute("SELECT pg_advisory_unlock(76016, #{@batch.id.to_i})") if locked
  end

  def run_next
    last_sent = @batch.items.where(status: 'sent').maximum(:updated_at)
    wait = last_sent && (last_sent + @assistant.response_delay_seconds.seconds - Time.current)
    return @batch.continue_later(wait: wait.ceil) if wait && wait.positive?

    sending = @batch.items.find_by(status: 'sending')
    if sending
      state = sending.conversation.marcosx_ai_conversation_state
      return @batch.continue_later(wait: 10) if state&.current_run?(sending.run_token)

      sending.discard!
      sending.update!(status: 'skipped', reason: I18n.t('marcosx_ai.errors.batch_changed'))
    end
    item = @batch.items.where(status: %w[pending analyzing queued]).order(:id).first
    return @batch.update!(status: @batch.items.exists?(status: 'ready') ? 'ready' : 'completed') unless item

    unless current?(item)
      item.update!(status: 'skipped', reason: I18n.t('marcosx_ai.errors.batch_changed'))
      return @batch.continue_later
    end
    if item.status.in?(%w[pending analyzing])
      item.update!(status: 'analyzing')
      plan = MarcosxAi::BatchReplyPlanner.perform(item)
      if plan['voice_text'].present?
        audio = MarcosxAi::VoiceClient.new(assistant: @assistant).synthesize(plan['voice_text'])
        item.audio.attach(io: StringIO.new(audio), filename: 'reply.mp3', content_type: 'audio/mpeg')
      end
      return if @batch.reload.status == 'cancelled'
      return @batch.continue_later unless item.reload.status == 'analyzing'

      item.update!(plan: plan, status: @batch.mode == 'review' ? 'ready' : 'queued')
      return @batch.continue_later if @batch.mode == 'review'
    end
    deliver(item)
  rescue StandardError => e
    item&.update!(status: 'failed', reason: I18n.t('marcosx_ai.errors.batch_failed')) unless item&.reload&.status == 'discarded'
    Rails.logger.warn("MarcoXIA batch #{@batch.id} failed: #{e.class.name}")
    @batch.continue_later unless @batch.reload.status == 'cancelled'
  end

  def current?(item)
    @assistant.account.account_users.exists?(user: @batch.user, role: :administrator) &&
      @assistant.reload.available? && item.assistant_version == @assistant.updated_at.iso8601(6) &&
      @pending.eligible?(item.conversation.reload, trigger_id: item.trigger_message_id)
  end

  def deliver(item)
    state = MarcosxAi::ConversationState.for_conversation!(item.conversation, assistant: @assistant)
    token = SecureRandom.uuid
    state.with_lock do
      return skip(item) unless current?(item) && @batch.reload.status != 'cancelled' && item.reload.status == 'queued'

      state.resume! if state.status == 'error'

      runtime = MarcosxAi::PromptBuilder.context_for(item.conversation, assistant: @assistant)
      plan = MarcosxAi::ReplyPlan.parse(item.plan.to_json, assistant: @assistant, conversation: item.conversation,
                                                           pix_available: runtime[:pix_available])
      return skip(item) if @batch.mode == 'review' && plan['resource_ids'] != item.plan['resource_ids']

      item.update!(status: 'sending', run_token: token)
      @batch.update!(status: 'running')
      state.update!(metadata: state.metadata.merge(
        'run_token' => token, 'trigger_message_id' => item.trigger_message_id, 'assistant_version' => item.assistant_version,
        'approved_draft' => true, 'processing' => true, 'reply_batch_item_id' => item.id
      ))
      plan = MarcosxAi::AlertService.prepare_delivery(state: state, plan: plan, token: token)
      return skip(item) unless plan

      state.update!(metadata: state.metadata.merge('pending_response' => plan.merge('next_part' => 0),
                                                   'approved_draft' => true, 'reply_batch_item_id' => item.id))
    end
    MarcosxAi::DeliveryJob.perform_later(item.conversation_id, token, 0)
    @batch.continue_later(wait: 10)
  end

  def skip(item)
    item.discard!
    item.update!(status: 'skipped', reason: I18n.t('marcosx_ai.errors.batch_changed'))
    @batch.continue_later
  end
end
