class Webhooks::WhatsmeowController < ActionController::API
  def process_payload
    channel = Channel::Whatsmeow.find_by(id: params[:channel_id])
    if channel.blank?
      render json: { error: 'Channel not found' }, status: :not_found
      return
    end

    if params[:event] == 'message'
      Whatsmeow::IncomingMessageService.new(inbox: channel.inbox, params: params.to_unsafe_hash).perform
    elsif params[:event] == 'paired'
      # Can do logging or additional pairing hooks if needed
      Rails.logger.info("Whatsmeow Channel #{channel.id} paired successfully!")
    end

    head :ok
  end
end
