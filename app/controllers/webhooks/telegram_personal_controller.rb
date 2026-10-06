class Webhooks::TelegramPersonalController < ActionController::API
  before_action :verify_token

  def process_payload
    inbox = Inbox.find_by!(account_id: params[:account_id], id: params[:inbox_id], channel_type: 'Channel::TelegramPersonal')
    inbox.with_lock do
      TelegramPersonal::IncomingEventService.new(inbox: inbox, payload: params.require(:payload).to_unsafe_h).perform
    end
    head :ok
  end

  private

  def verify_token
    token = ENV.fetch('TELEGRAM_PERSONAL_SHARED_SECRET', '')
    provided = request.headers['Authorization'].to_s.delete_prefix('Bearer ')
    head :unauthorized if token.blank? || !ActiveSupport::SecurityUtils.secure_compare(token, provided)
  end
end
