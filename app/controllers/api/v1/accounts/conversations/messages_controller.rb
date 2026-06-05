class Api::V1::Accounts::Conversations::MessagesController < Api::V1::Accounts::Conversations::BaseController
  before_action :ensure_api_inbox, only: :update

  def index
    @messages = message_finder.perform
  end

  def create
    user = Current.user || @resource
    mb = Messages::MessageBuilder.new(user, @conversation, params)
    @message = mb.perform
  rescue StandardError => e
    render_could_not_create_error(e.message)
  end

  def update
    Messages::StatusUpdateService.new(message, permitted_params[:status], permitted_params[:external_error]).perform
    @message = message
  end

  def destroy
    @message = message
    if locally_deleted_message?
      message_id = @message.id
      @message.destroy!
      render json: { id: message_id, conversation_id: @conversation.display_id, permanently_deleted: true }
      return
    end

    @message.update!(content_attributes: deleted_content_attributes)
  end

  def delete_for_everyone
    @message = Whatsmeow::DeleteMessageService.new(message: message, actor: Current.user).perform
  rescue StandardError => e
    render_could_not_create_error(e.message)
  end

  def retry
    return if message.blank?

    service = Messages::StatusUpdateService.new(message, 'sent')
    service.perform
    message.update!(content_attributes: {})
    ::SendReplyJob.perform_later(message.id)
  rescue StandardError => e
    render_could_not_create_error(e.message)
  end

  def reaction
    @message = Whatsmeow::ReactionService.new(
      message: message,
      emoji: permitted_params[:emoji],
      actor: Current.user
    ).perform
  rescue StandardError => e
    render_could_not_create_error(e.message)
  end

  def translate
    return head :ok if already_translated_content_available?

    translated_content = Integrations::GoogleTranslate::ProcessorService.new(
      message: message,
      target_language: permitted_params[:target_language]
    ).perform

    if translated_content.present?
      translations = {}
      translations[permitted_params[:target_language]] = translated_content
      translations = message.translations.merge!(translations) if message.translations.present?
      message.update!(translations: translations)
    end

    render json: { content: translated_content }
  end

  private

  def message
    @message ||= @conversation.messages.find(permitted_params[:id])
  end

  def message_finder
    @message_finder ||= MessageFinder.new(@conversation, params)
  end

  def permitted_params
    params.permit(:id, :target_language, :status, :external_error, :emoji)
  end

  def already_translated_content_available?
    message.translations.present? && message.translations[permitted_params[:target_language]].present?
  end

  def deleted_content_attributes
    (message.content_attributes || {}).merge(
      deleted: true,
      deleted_at: Time.current.to_i,
      deleted_by: Current.user&.id
    )
  end

  def locally_deleted_message?
    attributes = message.content_attributes || {}
    deleted = attributes['deleted'] || attributes[:deleted]
    deleted_by = attributes['deleted_by'] || attributes[:deleted_by]

    ActiveModel::Type::Boolean.new.cast(deleted) && deleted_by.present?
  end

  # API inbox check
  def ensure_api_inbox
    # Only API inboxes can update messages
    render json: { error: 'Message status update is only allowed for API inboxes' }, status: :forbidden unless @conversation.inbox.api?
  end
end
