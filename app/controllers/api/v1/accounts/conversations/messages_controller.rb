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

  def edit
    @message = Whatsmeow::EditMessageService.new(
      message: message,
      content: permitted_params[:content],
      actor: Current.user
    ).perform
  rescue StandardError => e
    render_could_not_create_error(e.message)
  end

  def retry
    return if message.blank?
    if message.content_attributes.key?('whatsmeow_pix') || message.content_attributes.key?('whatsmeowPix')
      return render_could_not_create_error(I18n.t('errors.whatsmeow.pix.retry_unavailable'))
    end

    ::SendReplyJob.perform_later(message.id) if claim_message_retry
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
  rescue Google::Cloud::Error => e
    # `details` carries the clean human message; `message` includes gRPC debug noise
    render_could_not_create_error(e.details.presence || e.message)
  end

  def transcribe_audio
    render_audio_processing_result(:transcribe)
  end

  def summarize_audio
    render_audio_processing_result(:summarize)
  end

  private

  def message
    @message ||= @conversation.messages.find(permitted_params[:id])
  end

  def message_finder
    @message_finder ||= MessageFinder.new(@conversation, params)
  end

  def claim_message_retry
    message.with_lock do
      next false unless message.failed?

      Messages::StatusUpdateService.new(message, 'sent').perform
      previous_source_id = message.source_id
      retry_attributes = { content_attributes: retry_content_attributes }
      retry_attributes[:source_id] = nil unless @conversation.inbox.api? || @conversation.inbox.web_widget?
      message.update!(retry_attributes)
      if retry_attributes.key?(:source_id) && previous_source_id.present?
        Rails.logger.info "Cleared older source ID #{previous_source_id} for message #{message.id}"
      end
      true
    end
  end

  def retry_content_attributes
    return message.content_attributes if message.content_attributes.dig('whatsapp_contact_info', 'type') == 'request'

    {}
  end

  def permitted_params
    params.permit(:id, :target_language, :status, :external_error, :emoji, :content, :attachment_id, :summary_type)
  end

  def render_audio_processing_result(operation)
    result = Messages::AudioTranscriptionService.new(
      audio_attachment,
      operation: operation,
      summary_type: permitted_params[:summary_type]
    ).perform

    if result[:success]
      @message = message.reload
      render :create
    else
      render json: { error: result[:error] }, status: :unprocessable_entity
    end
  end

  def audio_attachment
    attachments = message.attachments.audio
    return attachments.find(permitted_params[:attachment_id]) if permitted_params[:attachment_id].present?

    attachments.first
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

Api::V1::Accounts::Conversations::MessagesController.prepend_mod_with('Api::V1::Accounts::Conversations::MessagesController')
