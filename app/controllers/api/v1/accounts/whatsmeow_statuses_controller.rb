class Api::V1::Accounts::WhatsmeowStatusesController < Api::V1::Accounts::BaseController
  before_action :set_inbox, only: [:index, :create]
  before_action :set_status, only: [:view]

  def index
    statuses = @inbox.whatsmeow_statuses.active
                     .includes(:created_by, { contact: { avatar_attachment: :blob } }, media_attachment: :blob)
                     .order(:posted_at).to_a
    viewed_status_ids = Current.user.whatsmeow_status_views
                               .where(whatsmeow_status_id: statuses.map(&:id))
                               .pluck(:whatsmeow_status_id)
                               .index_with(true)
    render json: { payload: statuses.map { |status| status_payload(status, viewed_status_ids) } }
  end

  def create
    status = Whatsmeow::StatusPublisher.new(inbox: @inbox, user: Current.user, params: status_params).perform
    render json: { payload: status_payload(status, {}) }, status: :created
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    render json: { message: e.message }, status: :unprocessable_entity
  rescue Whatsmeow::SessionClient::Error => e
    render json: { message: e.message }, status: :bad_gateway
  end

  def view
    Whatsmeow::StatusViewService.new(status: @status, user: Current.user).perform
    render json: { payload: status_payload(@status.reload, @status.id => true) }
  end

  private

  def set_inbox
    @inbox = policy_scope(Current.account.inboxes).find(params.require(:inbox_id))
    authorize @inbox, action_name == 'create' ? :whatsmeow_status? : :show?
    head :not_found if @inbox.channel_type != 'Channel::Whatsmeow'
  end

  def set_status
    @status = Current.account.whatsmeow_statuses.active.find(params[:id])
    authorize @status.inbox, :show?
  end

  def status_params
    params.permit(:inbox_id, :content, :media, :background, :font)
  end

  def status_payload(status, viewed_status_ids)
    {
      id: status.id,
      inbox_id: status.inbox_id,
      contact: contact_payload(status.contact),
      sender_jid: status.sender_jid,
      sender_name: status.sender_name,
      sender_phone: status.sender_phone,
      from_me: status.from_me,
      status_type: status.status_type,
      content: status.content,
      media: media_payload(status),
      metadata: status.metadata,
      posted_at: status.posted_at.to_i,
      expires_at: status.expires_at.to_i,
      viewed: status.metadata['status_already_viewed'] || viewed_status_ids[status.id] || false,
      created_by: status.created_by&.name
    }
  end

  def contact_payload(contact)
    return if contact.blank?

    {
      id: contact.id,
      name: contact.name,
      phone_number: contact.phone_number,
      avatar_url: contact.avatar_url
    }
  end

  def media_payload(status)
    return unless status.media.attached?

    {
      url: url_for(status.media),
      content_type: status.media.content_type,
      filename: status.media.filename.to_s,
      byte_size: status.media.byte_size
    }
  end
end
