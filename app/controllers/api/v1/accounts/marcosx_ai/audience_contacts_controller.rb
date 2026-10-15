class Api::V1::Accounts::MarcosxAi::AudienceContactsController < Api::V1::Accounts::MarcosxAi::BaseController
  before_action :ensure_admin!

  def index
    Current.account.marcosx_ai_assistants.find(params[:assistant_id])
    query = params[:q].to_s.strip.first(100)
    contacts = Current.account.contacts.order(:name, :id)
    if query.present?
      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
      contacts = contacts.where('name ILIKE :q OR email ILIKE :q OR phone_number ILIKE :q', q: pattern)
    end
    render json: { contacts: contacts.limit(30).map { |contact| { id: contact.id, name: contact.name } } }
  end
end
