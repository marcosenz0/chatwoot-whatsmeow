class Webhooks::WhatsmeowController < ActionController::API
  def process_payload
    inbox = Inbox.find_by(id: params[:channel_id])
    if inbox.blank? || inbox.channel_type != 'Channel::Whatsmeow'
      render json: { error: 'Channel not found' }, status: :not_found
      return
    end

    channel = inbox.channel

    if params[:event] == 'message'
      Whatsmeow::IncomingMessageService.new(inbox: inbox, params: params.to_unsafe_hash).perform
    elsif params[:event] == 'paired'
      channel.update!(status: 'connected')
      Rails.logger.info("Whatsmeow Channel #{channel.id} paired successfully!")
    elsif params[:status].present?
      channel.update!(status: params[:status])
    end

    head :ok
  end
end
