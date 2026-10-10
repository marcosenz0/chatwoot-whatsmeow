class Api::V1::Accounts::MarcosxAi::ContactMemoriesController < Api::V1::Accounts::MarcosxAi::BaseController
  before_action :ensure_admin!
  before_action :set_contact, except: :index
  rescue_from ArgumentError do |error|
    render json: { error: error.message }, status: :unprocessable_entity
  end

  def index
    states = MarcosxAi::ConversationState.where(account: Current.account)
    states = states.where(assistant_id: params[:assistant_id]) if params[:assistant_id].present?
    ids = Current.account.conversations.where(id: states.select(:conversation_id)).select(:contact_id)
    scope = Current.account.contacts.where(id: ids).or(Current.account.contacts.where(
                                                         id: MarcosxAi::ContactMemory.where(account: Current.account).select(:contact_id)
                                                       ))
    scope = scope.where('name ILIKE ?', "%#{Contact.sanitize_sql_like(params[:q].to_s)}%") if params[:q].present?
    page = params[:page].to_i.clamp(1, 100_000)
    contacts = scope.order(:name, :id).offset((page - 1) * 25).limit(25)
    render json: { contacts: contacts.map { |contact| { id: contact.id, name: contact.name, avatar_url: contact.avatar_url } },
                   total: scope.count, page: page }
  end

  def show
    render json: contact_data
  end

  def update
    payload = params.require(:memory)
    if payload.key?(:summary)
      conversation = @contact.conversations.find_by!(display_id: payload.fetch(:conversation_id), account_id: Current.account.id)
      authorize conversation, :show?
      state = MarcosxAi::ConversationState.find_by!(conversation: conversation)
      summary = payload[:summary]
      raise ArgumentError, 'Invalid summary' unless summary.is_a?(String) && summary.length <= 30_000

      memory_record.with_lock do
        state.with_lock do
          state.update!(metadata: state.metadata.except(*MarcosxAi::ContactMemory::CACHE_KEYS).merge(
            'run_token' => SecureRandom.uuid, 'processing' => false
          ))
          scope = MarcosxAi::ConversationContext.public_history(conversation).reorder(created_at: :desc, id: :desc)
          recent = scope.limit(state.metadata['context_messages_limit'] || state.assistant&.history_limit || 80).to_a
          older = recent.empty? ? scope.none : scope.where('(created_at, id) < (?, ?)', recent.last.created_at, recent.last.id)
          last = older.first
          state.update!(metadata: state.metadata.merge(
            'conversation_summary' => summary, 'summary_manually_edited' => true, 'summary_updated_at' => Time.current.iso8601,
            'summary_cursor' => last && { 'created_at' => last.created_at.iso8601(6), 'id' => last.id },
            'summary_signature' => MarcosxAi::ConversationContext.signature(older), 'summary_messages_count' => older.count
          ))
        end
        memory_record.invalidate_dependents!(conversation.id)
      end
    else
      id = payload.fetch(:message_id)
      raise ArgumentError, 'Invalid message' unless id.is_a?(Integer) && id.positive? && [true, false].include?(payload[:excluded])

      conversation_ids = @contact.conversations.where(account: Current.account).select(:id)
      message = Current.account.messages.where(conversation_id: conversation_ids).find(id)
      raise ActiveRecord::RecordNotFound unless MarcosxAi::ConversationContext.raw_public_history(message.conversation).exists?(id: id)

      authorize message.conversation, :show?
      memory_record.exclude!(message, restore: !payload[:excluded])
    end
    render json: contact_data
  end

  def forget
    memory_record.forget!
    render json: contact_data
  end

  private

  def set_contact
    @contact = Current.account.contacts.find(params[:id])
    authorize @contact, :show?
  end

  def memory_record
    MarcosxAi::ContactMemory.find_or_create_by!(account: Current.account, contact: @contact)
  end

  def contact_data
    record = MarcosxAi::ContactMemory.find_by(account: Current.account, contact: @contact)
    conversations = @contact.conversations.where(account: Current.account).includes(:inbox, :marcosx_ai_conversation_state)
    conversations = conversations.select { |conversation| policy(conversation).show? }
    selected = conversations.find { |conversation| conversation.display_id == params[:conversation_id].to_i } ||
               conversations.find(&:marcosx_ai_conversation_state) || conversations.first
    messages = selected ? MarcosxAi::ConversationContext.raw_public_history(selected) : Message.none
    messages = messages.where('messages.id > ? AND messages.created_at > ?', record.cutoff_message_id, record.forgotten_at) if record&.forgotten_at
    messages = messages.where('messages.id < ?', params[:before_id].to_i) if params[:before_id].present?
    { contact: { id: @contact.id, name: @contact.name, forgotten_at: record&.forgotten_at },
      conversations: conversations.map { |conversation|
        state = conversation.marcosx_ai_conversation_state
        { id: conversation.display_id, inbox: conversation.inbox.name, assistant: state&.assistant&.name,
          summary: state&.metadata&.[]('conversation_summary'), updated_at: state&.metadata&.[]('summary_updated_at'),
          summarized_count: state&.metadata&.fetch('summary_messages_count', 0), editable: state.present? }
      }, conversation_id: selected&.display_id,
      messages: messages.reorder(id: :desc).limit(51).map { |message|
        { id: message.id, content: message.processed_message_content.presence || message.content, created_at: message.created_at,
          incoming: message.incoming?, excluded: record&.excluded_message_ids&.include?(message.id) || false }
      } }
  end
end
