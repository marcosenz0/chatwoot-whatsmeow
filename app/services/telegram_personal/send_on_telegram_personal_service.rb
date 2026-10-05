class TelegramPersonal::SendOnTelegramPersonalService < Base::SendOnChannelService
  MAX_ATTACHMENT_BYTES = 50.megabytes

  def perform
    super
  rescue TelegramPersonal::SessionClient::Error => e
    message.update!(status: :failed, content_attributes: message.content_attributes.merge('external_error' => e.code))
  end

  private

  def channel_class = Channel::TelegramPersonal

  def perform_reply
    payload = {
      request_id: message.id.to_s,
      chat_id: contact_inbox.source_id,
      content: message.outgoing_content.to_s,
      reply_to: message.content_attributes['in_reply_to_external_id']&.split(':')&.last,
      attachments: attachments_payload
    }
    result = TelegramPersonal::SessionClient.new(inbox: inbox).send_message(payload)
    message.update!(source_id: result.fetch('source_id'), status: :sent,
                    external_source_ids: message.external_source_ids.merge('telegram_personal' => result.fetch('message_ids')))
  end

  def attachments_payload
    size = message.attachments.sum { |attachment| attachment.file.blob.byte_size }
    raise TelegramPersonal::SessionClient::Error, 'file_too_large' if size > MAX_ATTACHMENT_BYTES

    message.attachments.map do |attachment|
      blob = attachment.file.blob
      {
        filename: blob.filename.to_s,
        content_type: blob.content_type,
        file_type: attachment.file_type,
        voice: message.content_attributes['telegram_personal_recorded_audio'].present?,
        data: blob.open { |file| Base64.strict_encode64(file.read) }
      }
    end
  end
end
