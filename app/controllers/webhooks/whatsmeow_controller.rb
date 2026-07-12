class Webhooks::WhatsmeowController < ActionController::API
  EVENT_HANDLERS = {
    'message' => :process_message,
    'status' => :process_status,
    'status_view' => :process_status_view,
    'receipt' => :process_receipt,
    'reaction' => :process_reaction,
    'edit' => :process_edit,
    'delete' => :process_delete,
    'status_delete' => :delete_status,
    'paired' => :process_paired
  }.freeze

  before_action :verify_webhook_token

  def process_payload
    if inbox.blank? || inbox.channel_type != 'Channel::Whatsmeow'
      render json: { error: 'Channel not found' }, status: :not_found
      return
    end

    process_event
    head :ok
  end

  private

  def verify_webhook_token
    expected_token = ENV.fetch('WHATSMEOW_SHARED_SECRET', '')
    return if expected_token.blank?

    provided_token = request.headers['X-Whatsmeow-Internal-Token'].to_s
    head :unauthorized unless ActiveSupport::SecurityUtils.secure_compare(provided_token, expected_token)
  end

  def inbox
    @inbox ||= Inbox.find_by(id: params[:channel_id], account_id: params[:account_id])
  end

  def channel
    inbox.channel
  end

  def process_event
    handler = EVENT_HANDLERS[params[:event]]
    handler.present? ? send(handler) : update_status
  end

  def process_message
    return process_status if status_payload?

    Whatsmeow::IncomingMessageService.new(inbox: inbox, params: params.to_unsafe_hash).perform
  end

  def process_status
    Whatsmeow::IncomingStatusService.new(inbox: inbox, params: params.to_unsafe_hash).perform
  end

  def process_status_view
    Whatsmeow::StatusViewReceiptService.new(inbox: inbox, params: params.to_unsafe_hash).perform
  end

  def process_receipt
    Whatsmeow::ReceiptService.new(inbox: inbox, params: params.to_unsafe_hash).perform
  end

  def process_reaction
    Whatsmeow::ReactionService.apply_incoming(inbox: inbox, params: params.to_unsafe_hash)
  end

  def process_edit
    Whatsmeow::EditMessageService.apply_incoming(inbox: inbox, params: params.to_unsafe_hash)
  end

  def process_delete
    return delete_status if status_payload?

    Whatsmeow::DeleteMessageService.apply_incoming(inbox: inbox, params: params.to_unsafe_hash)
  end

  def process_paired
    channel.update!(status: 'connected')
    Whatsmeow::StatusContactCleanupJob.perform_later(inbox.id)
    Rails.logger.info("Whatsmeow Channel #{channel.id} paired successfully!")
  end

  def delete_status
    inbox.whatsmeow_statuses.find_by(source_id: params[:message_id])&.destroy!
  end

  def status_payload?
    return true if %w[status status_delete].include?(params[:event].to_s)

    [params[:chat], params[:sender], params[:sender_alt], params[:recipient_alt], params[:group_jid]].compact.any? do |jid|
      user, server = jid.to_s.downcase.split('@', 2)
      user.to_s.split(':').first == 'status' && server == 'broadcast'
    end
  end

  def update_status
    channel.update!(status: params[:status]) if params[:status].present?
  end
end
