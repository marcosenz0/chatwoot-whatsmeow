module Enterprise::Concerns::Attachment
  extend ActiveSupport::Concern

  included do
    # Broadcast the message update so the FE bubble picks up the new audio
    # attachment immediately after the file is attached.
    after_create_commit :broadcast_message_update_for_audio
  end

  private

  def broadcast_message_update_for_audio
    return unless file_type.to_sym == :audio
    return unless message
    # Without an attached file, the message serializer's audio_metadata path
    # dereferences `file.metadata[:width]` on nil and raises. The pre-attach
    # broadcast wouldn't carry useful audio info anyway — skip until upload completes.
    return unless file.attached?

    message.reload.send_update_event
  end
end
