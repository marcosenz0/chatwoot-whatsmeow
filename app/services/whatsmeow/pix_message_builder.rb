class Whatsmeow::PixMessageBuilder
  pattr_initialize [:actor!, :conversation!, :attributes]

  def perform
    ensure_whatsmeow_conversation!
    pix = explicit_payload? ? Whatsmeow::PixPayload.new(attributes) : configured_payload
    pix.validate!

    Messages::MessageBuilder.new(actor, conversation, message_params(pix), allow_whatsmeow_pix: true).perform
  end

  private

  def ensure_whatsmeow_conversation!
    return if conversation.inbox.channel_type == 'Channel::Whatsmeow'

    raise CustomExceptions::Whatsmeow::InvalidPixPayload.new(
      code: 'unsupported_channel',
      message: I18n.t('errors.whatsmeow.pix.unsupported_channel')
    )
  end

  def configured_payload
    channel = conversation.inbox.channel
    return Whatsmeow::PixPayload.from_channel(channel) if channel.pix_configured?

    raise CustomExceptions::Whatsmeow::InvalidPixPayload.new(
      code: 'pix_not_configured',
      message: I18n.t('errors.whatsmeow.pix.not_configured')
    )
  end

  def explicit_payload?
    attributes.to_h.any?
  end

  def message_params(pix)
    {
      content: pix.merchant_name,
      content_type: 'text',
      message_type: 'outgoing',
      private: false,
      content_attributes: { whatsmeow_pix: pix.to_h }
    }
  end
end
