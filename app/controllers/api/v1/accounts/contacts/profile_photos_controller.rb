class Api::V1::Accounts::Contacts::ProfilePhotosController < Api::V1::Accounts::BaseController
  rescue_from Whatsmeow::SessionClient::Error, with: :render_service_error

  def show
    contact = Current.account.contacts.find(params[:contact_id])
    authorize contact, :show?
    inbox = Current.account.inboxes.find(params[:inbox_id]) if params[:inbox_id].present?
    authorize inbox, :show? if inbox

    if inbox&.channel_type == 'Channel::Whatsmeow'
      source_id = contact.contact_inboxes.find_by(inbox: inbox)&.source_id
      raise ActiveRecord::RecordNotFound if source_id.blank?

      render json: Whatsmeow::SessionClient.new(inbox: inbox).full_profile_photo(source_id)
    else
      url = contact.avatar.attached? ? url_for(contact.avatar) : ''
      render json: { photo_url: url, photo_status: url.present? ? 'available' : 'none' }
    end
  end

  private

  def render_service_error(error)
    render json: { message: error.message }, status: :unprocessable_entity
  end
end
