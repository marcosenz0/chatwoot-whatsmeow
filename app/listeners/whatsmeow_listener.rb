class WhatsmeowListener < BaseListener
  def conversation_typing_on(event)
    send_typing_status(event, 'on')
  end

  def conversation_typing_off(event)
    send_typing_status(event, 'off')
  end

  private

  def send_typing_status(event, status)
    return unless event.data[:user].is_a?(User)
    return if ActiveModel::Type::Boolean.new.cast(event.data[:is_private])

    Whatsmeow::TypingStatusService.new(
      conversation: event.data[:conversation],
      status: status,
      media: event.data[:typing_media]
    ).perform
  end
end
