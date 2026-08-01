require 'base64'

class Whatsmeow::StatusReplyService
  MAXIMUM_CONTENT_LENGTH = 4096
  MAXIMUM_REACTION_LENGTH = 64

  pattr_initialize [:status!, :params!, :sticker]

  def perform
    validate_payload!
    Whatsmeow::SessionClient.new(inbox: status.inbox).reply_to_status(payload)
  end

  private

  def validate_payload!
    validate_reply_target!
    validate_content!
    validate_reaction!
    validate_response_type!
    validate_sticker!
  end

  def validate_reply_target!
    raise ArgumentError, 'You cannot reply to your own Status' if status.from_me?
  end

  def validate_content!
    raise ArgumentError, 'Status reply content is too long' if content.length > MAXIMUM_CONTENT_LENGTH
  end

  def validate_reaction!
    raise ArgumentError, 'Status reaction is too long' if reaction.length > MAXIMUM_REACTION_LENGTH
  end

  def validate_response_type!
    raise ArgumentError, 'A text, reaction, or sticker is required' if response_type.blank?
    raise ArgumentError, 'Choose only one type of Status response' if response_type_count > 1
  end

  def validate_sticker!
    return if sticker.blank? || sticker_file_attached?

    raise ArgumentError, 'The sticker file is unavailable'
  end

  def payload
    {
      message_id: status.source_id,
      sender_jid: status.sender_jid,
      timestamp: status.posted_at.to_i,
      content: content.presence,
      reaction: reaction.presence,
      sticker: sticker_payload
    }.compact_blank
  end

  def content
    @content ||= params[:content].to_s.strip
  end

  def reaction
    @reaction ||= params[:reaction].to_s.strip
  end

  def response_type
    return :sticker if sticker.present?
    return :reaction if reaction.present?
    return :content if content.present?
  end

  def response_type_count
    [content.present?, reaction.present?, sticker.present?].count(true)
  end

  def sticker_file_attached?
    sticker.attachment&.file&.attached?
  end

  def sticker_payload
    return if sticker.blank?

    attachment = sticker.attachment
    {
      file_name: attachment.file.filename.to_s,
      content_type: attachment.file.content_type.presence || 'image/webp',
      file_type: 'sticker',
      meta: { whatsmeow_sticker: true },
      data_base64: sticker_data(attachment)
    }
  end

  def sticker_data(attachment)
    attachment.file.blob.open { |file| Base64.strict_encode64(file.read) }
  rescue ActiveStorage::FileNotFoundError, ActiveStorage::IntegrityError
    raise ArgumentError, 'The sticker file is unavailable'
  end
end
