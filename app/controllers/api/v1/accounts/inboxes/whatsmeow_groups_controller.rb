class Api::V1::Accounts::Inboxes::WhatsmeowGroupsController < Api::V1::Accounts::BaseController
  before_action :fetch_inbox
  rescue_from Whatsmeow::SessionClient::Error, with: :render_service_error

  def show
    render json: client.group_details(params.require(:group_jid))
  end

  def create
    payload = client.create_group(group_params)
    conversation = Whatsmeow::GroupConversationBuilder.new(
      inbox: @inbox, params: { group_jid: payload.fetch('group_jid'), group_name: payload.fetch('group_name'), participant_count: payload['count'] }
    ).perform
    render json: payload.merge(conversation_id: conversation.display_id), status: :created
  end

  def update
    payload = client.update_group(group_params)
    contact = @inbox.contact_inboxes.find_by(source_id: payload.fetch('group_jid'))&.contact
    contact&.update!(name: payload.fetch('group_name'))
    Whatsmeow::ProfilePictureSyncJob.perform_later(contact.id, @inbox.id, payload.fetch('group_jid'), force: true) if contact && group_params.key?('photo')
    render json: payload
  end

  def action
    render json: client.group_action(params.permit(:group_jid, :operation, :community_jid, participants: []).to_h)
  end

  def contacts
    render json: client.group_contacts(params.permit(:q, :offset).to_h)
  end

  def requests
    render json: client.group_requests(params.require(:group_jid))
  end

  private

  def fetch_inbox
    @inbox = Current.account.inboxes.find(params[:inbox_id])
    authorize @inbox, :show?
    raise ActiveRecord::RecordNotFound unless @inbox.channel_type == 'Channel::Whatsmeow'
  end

  def client
    @client ||= Whatsmeow::SessionClient.new(inbox: @inbox)
  end

  def group_params
    params.permit(:group_jid, :name, :topic, :photo, :allow_member_edit, :allow_member_send,
                  :allow_member_add, :require_approval, :disappearing_timer, participants: []).to_h
  end

  def render_service_error(error)
    render json: { message: error.message }, status: :unprocessable_entity
  end
end
