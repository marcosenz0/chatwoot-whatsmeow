class Whatsmeow::CallMessageService
  pattr_initialize [:call!]

  def perform
    call.with_lock do
      message = call.conversation.messages.find_or_initialize_by(source_id: "whatsmeow-call:#{call.source_id}")
      message.assign_attributes(
        account: call.account, inbox: call.inbox, content_type: :voice_call,
        message_type: call.direction, sender: call.direction == 'incoming' ? call.contact : call.agent,
        content: I18n.t("messages.whatsmeow_call.#{call.video ? 'video' : 'voice'}", locale: call.account.locale),
        created_at: call.started_at,
        content_attributes: {
          historical: true, skip_send_reply_job: true, external_echo: call.direction == 'outgoing',
          whatsmeow_call: {
            id: call.id, direction: call.direction, status: call.status, video: call.video,
            duration_seconds: call.duration_seconds, end_reason: call.end_reason
          }
        }
      )
      message.save!
    end
  end
end
