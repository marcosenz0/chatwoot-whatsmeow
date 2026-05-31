class Webhooks::WhatsmeowController < ActionController::API
  def process_payload
    if inbox.blank? || inbox.channel_type != 'Channel::Whatsmeow'
      render json: { error: 'Channel not found' }, status: :not_found
      return
    end

    process_event
    head :ok
  end

  private

  def inbox
    @inbox ||= Inbox.find_by(id: params[:channel_id])
  end

  def channel
    inbox.channel
  end

  def process_event
    case params[:event]
    when 'message'
      Whatsmeow::IncomingMessageService.new(inbox: inbox, params: params.to_unsafe_hash).perform
    when 'receipt'
      Whatsmeow::ReceiptService.new(inbox: inbox, params: params.to_unsafe_hash).perform
    when 'paired'
      channel.update!(status: 'connected')
      Rails.logger.info("Whatsmeow Channel #{channel.id} paired successfully!")
    else
      update_status
    end
  end

  def update_status
    channel.update!(status: params[:status]) if params[:status].present?
  end
end
