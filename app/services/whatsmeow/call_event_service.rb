class Whatsmeow::CallEventService
  pattr_initialize [:inbox!, :params!]

  def perform
    call = find_call
    update_call(call)
    apply_event(call)
    call.save!
    Whatsmeow::CallMessageService.new(call: call).perform if call.ended_at
  end

  private

  def find_call
    WhatsmeowCall.find_or_initialize_by(inbox: inbox, source_id: params.fetch('call_id'))
  end

  def update_call(call)
    call.assign_attributes(account: inbox.account, peer_jid: params.fetch('peer_jid'), direction: params.fetch('direction')) if call.new_record?
    call.started_at = [call.started_at, event_time].compact.min
    call.video ||= ActiveModel::Type::Boolean.new.cast(params['video'])
    call.agent_id ||= params['agent_id'].presence
    attach_contact(call)
  end

  def apply_event(call)
    case params.fetch('event')
    when 'call_connected'
      connect_call(call)
    when 'call_ended'
      end_call(call)
    end
  end

  def connect_call(call)
    return if call.ended_at

    call.status = 'connected'
    call.connected_at ||= connected_time
  end

  def end_call(call)
    return if call.ended_at

    call.ended_at = event_time
    call.end_reason = params['reason'].to_s.first(255)
    call.connected_at ||= connected_time if params['connected_at'].present?
    call.status = final_status(call)
  end

  def event_time
    @event_time ||= Time.zone.at(params.fetch('timestamp').to_i)
  end

  def connected_time
    Time.zone.at(params.fetch('connected_at').to_i)
  end

  def attach_contact(call)
    return if call.conversation_id

    if params['conversation_id'].present?
      call.conversation = inbox.conversations.find(params.fetch('conversation_id'))
      call.contact = call.conversation.contact
      return
    end

    source_ids = [call.peer_jid, params['phone_jid']].compact_blank.uniq
    contact_inbox = inbox.contact_inboxes.where(source_id: source_ids).includes(:contact).first
    call.conversation = contact_inbox&.conversations&.order(id: :desc)&.first
    call.conversation ||= Whatsmeow::DirectConversationBuilder.new(
      inbox: inbox,
      params: { participant_jid: params['phone_jid'].presence || call.peer_jid, participant_lid_jid: call.peer_jid }
    ).perform
    call.contact = call.conversation.contact
  end

  def final_status(call)
    return 'completed' if call.connected_at
    return 'declined' if call.end_reason.match?(/reject|declin/i)

    call.direction == 'incoming' ? 'missed' : 'unanswered'
  end
end
