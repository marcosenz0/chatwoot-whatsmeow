class Api::V1::Accounts::MarcosxAi::ReplyBatchesController < Api::V1::Accounts::MarcosxAi::BaseController
  before_action :ensure_admin!
  before_action :set_assistant
  rescue_from ArgumentError, ActiveRecord::RecordNotUnique, CustomExceptions::MarcosxAi do
    render json: { error: I18n.t('marcosx_ai.errors.batch_invalid') }, status: :unprocessable_entity
  end

  def index
    pending = MarcosxAi::PendingConversations.new(assistant: @assistant, user: Current.user)
    scope = pending.scope
    if params[:search].present?
      scope = scope.where('contacts.name ILIKE ?', "%#{ActiveRecord::Base.sanitize_sql_like(params[:search])}%")
    end
    scope = scope.where("NOT EXISTS (SELECT 1 FROM marcosx_ai_reply_batch_items reserved WHERE reserved.conversation_id = conversations.id " \
                        "AND reserved.trigger_message_id = pending_message.id AND reserved.status NOT IN ('discarded', 'failed', 'skipped'))")
    page = params[:page].to_i.clamp(1, 100_000)
    recent = @assistant.reply_batches.where(user: Current.user).order(id: :desc).first
    render json: { total: scope.count, page: page,
                   conversations: scope.offset((page - 1) * 25).limit(25).map { |c| pending.data(c).merge(trigger_message_id: pending.latest(c).id) },
                   batch: recent&.public_data }
  end

  def preview
    conversation = @assistant.account.conversations.find_by!(display_id: params[:conversation_id])
    authorize conversation, :show?
    history = MarcosxAi::ConversationContext.public_history(conversation).reorder(id: :desc).limit(20).to_a.reverse
    render json: { messages: history.map { |m| { id: m.id, incoming: m.incoming?, content: m.content_attributes['marcosx_ai_voice_transcript'].presence ||
                                                                                     m.content.presence || m.attachments.first&.file_type,
                                                sent_at: m.created_at.iso8601 } } }
  end

  def create
    mode = params[:mode]
    selections = params[:selections]
    request_id = params[:request_id]
    unless %w[review direct].include?(mode) && request_id.is_a?(String) && request_id.length.between?(1, 80) && selections.is_a?(Array) &&
           selections.present? && selections.all? { |s| s[:id].is_a?(Integer) && s[:trigger_message_id].is_a?(Integer) } &&
           selections.pluck(:id).uniq.size == selections.size
      raise ArgumentError
    end
    raise ArgumentError unless @assistant.available?

    batch = @assistant.reply_batches.find_by(user: Current.user, request_id: request_id)
    unless batch
      pending = MarcosxAi::PendingConversations.new(assistant: @assistant, user: Current.user)
      batch = @assistant.reply_batches.transaction do
        record = @assistant.reply_batches.create!(account: Current.account, user: Current.user, mode: mode, request_id: request_id)
        selections.each do |selected|
          conversation = @assistant.account.conversations.find_by!(display_id: selected[:id])
          authorize conversation, :show?
          eligible = pending.eligible?(conversation, trigger_id: selected[:trigger_message_id])
          record.items.create!(conversation: conversation, trigger_message_id: selected[:trigger_message_id],
                               assistant_version: @assistant.updated_at.iso8601(6), status: eligible ? 'pending' : 'skipped',
                               reason: eligible ? nil : I18n.t('marcosx_ai.errors.batch_changed'))
        end
        record
      end
      batch.continue_later
    end
    render json: { batch: batch.public_data }, status: :accepted
  end

  def show
    render json: { batch: batch.public_data }
  end

  def update
    record = batch
    case params[:operation]
    when 'cancel'
      record.cancel!
    when 'discard'
      item = record.items.find(params[:item_id])
      raise ArgumentError unless item.status.in?(%w[ready pending analyzing])

      item.discard!
    when 'send'
      record.with_lock do
        if record.status == 'ready'
          record.items.where(status: 'ready').update_all(status: 'queued', updated_at: Time.current)
          record.update!(status: 'running')
          record.continue_later
        end
      end
    else
      raise ArgumentError
    end
    render json: { batch: record.reload.public_data }
  end

  private

  def set_assistant
    @assistant = Current.account.marcosx_ai_assistants.find(params[:assistant_id])
  end

  def batch
    @assistant.reply_batches.where(user: Current.user).find(params[:id])
  end
end
