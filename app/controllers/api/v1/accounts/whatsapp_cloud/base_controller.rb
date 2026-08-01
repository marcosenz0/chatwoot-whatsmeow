class Api::V1::Accounts::WhatsappCloud::BaseController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?

  private

  def official_inbox(inbox_id = params[:inbox_id])
    @official_inboxes ||= {}
    @official_inboxes[inbox_id.to_i] ||= Current.account.inboxes.find(inbox_id).tap do |inbox|
      unless inbox.channel_type == 'Channel::Whatsapp' && inbox.channel.provider == 'whatsapp_cloud'
        raise ActiveRecord::RecordNotFound, 'Official WhatsApp Cloud API inbox not found'
      end
    end
  end
end
