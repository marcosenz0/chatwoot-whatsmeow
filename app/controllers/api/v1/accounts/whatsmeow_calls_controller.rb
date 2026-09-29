class Api::V1::Accounts::WhatsmeowCallsController < Api::V1::Accounts::BaseController
  def index
    accessible_ids = policy_scope(Current.account.inboxes).where(channel_type: 'Channel::Whatsmeow').select(:id)
    calls = WhatsmeowCall.where(account: Current.account, inbox_id: accessible_ids)
                         .includes(:inbox, :conversation, contact: { avatar_attachment: :blob })
                         .order(started_at: :desc).limit(100)
    render json: { payload: calls.map { |call| call_payload(call) } }
  end

  def create_link
    inbox = accessible_inboxes.find(params.require(:inbox_id))
    result = Whatsmeow::SessionClient.new(inbox: inbox).create_call_link(video: ActiveModel::Type::Boolean.new.cast(params[:video]))
    render json: { payload: result }
  rescue Whatsmeow::SessionClient::Error => e
    render json: { message: e.message }, status: :bad_gateway
  end

  def dial
    inbox = accessible_inboxes.find(params.require(:inbox_id))
    phone = params.require(:phone_number).to_s.gsub(/\D/, '')
    return render json: { message: 'Número inválido: informe DDI e DDD.' }, status: :unprocessable_entity unless phone.match?(/\A[1-9]\d{9,14}\z/)

    lookup = Whatsmeow::SessionClient.new(inbox: inbox).check_number("+#{phone}")
    return render json: { message: 'Este número não está no WhatsApp.' }, status: :unprocessable_entity unless lookup['is_on_whatsapp']

    conversation = dial_conversation(inbox, phone, lookup)
    render json: { payload: { conversation_id: conversation.display_id } }
  rescue Whatsmeow::SessionClient::Error => e
    render json: { message: e.message }, status: :bad_gateway
  end

  private

  def accessible_inboxes
    policy_scope(Current.account.inboxes).where(channel_type: 'Channel::Whatsmeow')
  end

  def dial_conversation(inbox, phone, lookup)
    contact_inbox = Whatsmeow::ContactIdentityResolver.new(
      inbox: inbox,
      source_ids: [lookup['jid'].presence || "#{phone}@s.whatsapp.net"],
      phone_number: "+#{phone}",
      contact_attributes: { name: "+#{phone}", additional_attributes: {} }
    ).perform
    contact_inbox.conversations.where.not(status: :resolved).order(id: :desc).first ||
      contact_inbox.conversations.order(id: :desc).first ||
      Conversation.create!(account: Current.account, inbox: inbox, contact: contact_inbox.contact, contact_inbox: contact_inbox)
  end

  def call_payload(call)
    {
      id: call.id,
      inbox_id: call.inbox_id,
      inbox_name: call.inbox.name,
      conversation_id: call.conversation&.display_id,
      contact_id: call.contact_id,
      **call_identity(call),
      direction: call.direction,
      status: call.status,
      video: call.video,
      started_at: call.started_at,
      duration_seconds: call.duration_seconds
    }
  end

  def call_identity(call)
    phone = call.contact&.phone_number.presence
    peer_number = call.peer_jid.split('@').first
    {
      name: call.contact&.name.presence || phone || peer_number,
      phone_number: phone || ("+#{peer_number}" if call.peer_jid.end_with?('@s.whatsapp.net')),
      avatar_url: call.contact&.avatar_url
    }
  end
end
