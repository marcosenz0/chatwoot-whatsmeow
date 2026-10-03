class Api::V1::Accounts::Conversations::InstagramPreviewsController < Api::V1::Accounts::Conversations::BaseController
  def show
    message = @conversation.messages.find(params[:message_id])
    candidates = [message.content.to_s.strip, *message.attachments.pluck(:external_url)]
    target = candidates.filter_map { |url| Instagram::PreviewUrl.parse(url) }.find { |item| item[:url] == params[:url] }
    return head :unprocessable_entity unless target

    render json: Instagram::PreviewService.new(url: target[:url]).perform
  end
end
