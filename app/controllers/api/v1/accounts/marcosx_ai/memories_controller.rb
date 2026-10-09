class Api::V1::Accounts::MarcosxAi::MemoriesController < Api::V1::Accounts::MarcosxAi::BaseController
  before_action :set_state
  rescue_from ArgumentError do |error|
    render json: { error: error.message }, status: :unprocessable_entity
  end

  def show
    render json: { memory: memory_data }
  end

  def update
    mode = params.require(:memory).fetch(:mode)
    limit = params.require(:memory).fetch(:recent_limit)
    raise ArgumentError, 'Invalid memory options' unless %w[summary_recent selected_only].include?(mode) &&
                                                         limit.is_a?(Integer) && limit.between?(1, 300)

    @state.with_lock do
      @state.update!(metadata: @state.metadata.merge('memory_mode' => mode, 'context_messages_limit' => limit,
                                                     'run_token' => SecureRandom.uuid, 'processing' => false)
                                    .except('pending_response', 'approved_draft', 'analysis', 'memory_rebuild'))
    end
    render json: { memory: memory_data }
  end

  def create
    raise ArgumentError, I18n.t('marcosx_ai.errors.credential_missing') unless @state.assistant.available?

    mode = @state.metadata['memory_mode'] || @state.assistant.memory_mode
    raise ArgumentError, 'Select summary memory first' unless mode == 'summary_recent'

    token = SecureRandom.uuid
    @state.with_lock do
      @state.update!(metadata: @state.metadata.except('conversation_summary', 'summary_cursor', 'summary_signature', 'summary_messages_count')
                                     .merge('memory_rebuild' => { 'id' => token, 'status' => 'processing' }))
    end
    MarcosxAi::MemoryRebuildJob.perform_later(@state.id, token)
    render json: { memory: memory_data }, status: :accepted
  end

  def link
    id = params.require(:memory).fetch(:conversation_id)
    raise ArgumentError, 'Invalid conversation' unless id.is_a?(Integer) && id.positive?

    source = Current.account.conversations.find_by!(display_id: id)
    authorize source, :show?
    raise ArgumentError, 'Choose another channel' if source.id == @state.conversation_id || source.inbox_id == @state.inbox_id

    @state.with_lock do
      links = @state.metadata.fetch('approved_context_links', []).reject { |entry| entry['conversation_id'] == source.id }
      links << { 'conversation_id' => source.id, 'approved_by' => Current.user.id, 'approved_at' => Time.current.iso8601 }
      @state.update!(metadata: @state.metadata.merge('approved_context_links' => links))
    end
    render json: { memory: memory_data }
  end

  def unlink
    @state.with_lock { @state.update!(metadata: @state.metadata.except('approved_context_links')) }
    render json: { memory: memory_data }
  end

  private

  def set_state
    conversation = Current.account.conversations.find_by!(display_id: params[:conversation_id])
    authorize conversation, :show?
    @state = MarcosxAi::ConversationState.find_by!(conversation: conversation)
  end

  def memory_data
    @state.reload
    { mode: @state.metadata['memory_mode'] || @state.assistant.memory_mode,
      recent_limit: @state.metadata['context_messages_limit'] || @state.assistant.history_limit,
      summary: @state.metadata['conversation_summary'], updated_at: @state.metadata['summary_updated_at'],
      stale: MarcosxAi::ConversationContext.stale?(@state),
      summarized_count: @state.metadata.fetch('summary_messages_count', 0), rebuild: @state.metadata['memory_rebuild'],
      links: Current.account.conversations.where(id: @state.metadata.fetch('approved_context_links', []).map { |entry| entry['conversation_id'] })
                    .map { |conversation| { id: conversation.display_id, inbox: conversation.inbox.name } } }
  end
end
