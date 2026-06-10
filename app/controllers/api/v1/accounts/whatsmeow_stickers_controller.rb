require 'base64'
require 'stringio'

class Api::V1::Accounts::WhatsmeowStickersController < Api::V1::Accounts::BaseController
  before_action :set_sticker, only: [:destroy, :send_sticker]

  def index
    authorize WhatsmeowSticker

    stickers = current_user.whatsmeow_stickers
                           .where(account_id: Current.account.id)
                           .includes(attachment: { file_attachment: :blob })
                           .order(updated_at: :desc)

    render json: { payload: stickers.map { |sticker| sticker_payload(sticker) } }
  end

  def create
    authorize WhatsmeowSticker

    attachment = Attachment.where(account_id: Current.account.id).find(sticker_params[:attachment_id])
    return render json: { error: 'Attachment is not a WhatsApp sticker' }, status: :unprocessable_entity unless sticker_attachment?(attachment)

    sticker = current_user.whatsmeow_stickers.find_or_initialize_by(
      account: Current.account,
      attachment: attachment
    )
    sticker.metadata = sticker_metadata(attachment).merge(sticker_file_metadata(attachment))
    sticker.save!

    render json: { payload: sticker_payload(sticker) }
  end

  def destroy
    authorize @sticker

    @sticker.destroy!
    head :ok
  end

  def send_sticker
    authorize @sticker, :send?

    conversation = Current.account.conversations.find(sticker_params[:conversation_id])
    authorize conversation, :show?

    metadata = persisted_sticker_metadata(@sticker)
    return render_unavailable_sticker unless metadata[:data_base64].present?

    message = build_sticker_message(conversation, @sticker, metadata)
    deliver_sticker_message(message)

    render json: { payload: message.reload.push_event_data }
  end

  private

  def set_sticker
    @sticker = current_user.whatsmeow_stickers.where(account_id: Current.account.id).find(params[:id])
  end

  def sticker_params
    params.permit(:attachment_id, :conversation_id)
  end

  def sticker_attachment?(attachment)
    attachment.image? && attachment.file.attached? && sticker_metadata(attachment)['whatsmeow_sticker']
  end

  def sticker_metadata(attachment)
    (attachment.meta || {}).with_indifferent_access.merge(whatsmeow_sticker: true).stringify_keys
  end

  def sticker_file_metadata(attachment)
    return {} unless attachment.file.attached?

    {
      data_base64: Base64.strict_encode64(attachment.file.download),
      file_name: attachment.file.filename.to_s,
      content_type: attachment.file.content_type.presence || 'image/webp',
      file_size: attachment.file.byte_size
    }.compact
  end

  def persisted_sticker_metadata(sticker)
    metadata = (sticker.metadata || {}).with_indifferent_access
    return metadata if metadata[:data_base64].present?

    metadata = sticker_metadata(sticker.attachment).merge(sticker_file_metadata(sticker.attachment))
    sticker.update!(metadata: metadata)
    metadata.with_indifferent_access
  rescue ActiveStorage::FileNotFoundError, ActiveStorage::IntegrityError => e
    Rails.logger.warn("Whatsmeow sticker #{sticker.id} is unavailable: #{e.message}")
    metadata.merge(unavailable: true)
  end

  def build_sticker_message(conversation, sticker, metadata)
    message = conversation.messages.build(
      account: Current.account,
      inbox: conversation.inbox,
      message_type: :outgoing,
      status: :sent,
      sender: current_user,
      content_attributes: { whatsmeow_sticker: true, skip_send_reply_job: true }
    )

    attachment = message.attachments.build(
      account: Current.account,
      file_type: :image,
      meta: public_sticker_metadata(metadata).merge(whatsmeow_sticker: true).stringify_keys
    )
    attachment.file.attach(
      io: sticker_file_io(metadata),
      filename: metadata[:file_name].presence || "sticker-#{sticker.id}.webp",
      content_type: metadata[:content_type].presence || 'image/webp'
    )
    message.save!
    message
  end

  def sticker_file_io(metadata)
    io = StringIO.new(Base64.decode64(metadata[:data_base64]))
    io.set_encoding(Encoding::BINARY)
    io
  end

  def public_sticker_metadata(metadata)
    metadata.except(:data_base64, 'data_base64')
  end

  def sticker_data_url(metadata)
    return '' if metadata[:data_base64].blank?

    "data:#{metadata[:content_type].presence || 'image/webp'};base64,#{metadata[:data_base64]}"
  end

  def render_unavailable_sticker
    render json: { error: 'Sticker file is unavailable. Remove it from favorites and save it again.' }, status: :unprocessable_entity
  end

  def deliver_sticker_message(message)
    return unless message.conversation.inbox.channel_type == 'Channel::Whatsmeow'

    Whatsmeow::SendOnWhatsmeowService.new(message: message).perform
  end

  def sticker_payload(sticker)
    attachment = sticker.attachment
    metadata = persisted_sticker_metadata(sticker)
    data_url = sticker_data_url(metadata)

    {
      id: sticker.id,
      attachment_id: attachment.id,
      file_name: metadata[:file_name].presence || (attachment.file.attached? ? attachment.file.filename.to_s : ''),
      content_type: metadata[:content_type].presence || (attachment.file.attached? ? attachment.file.content_type : ''),
      data_url: data_url,
      thumb_url: data_url,
      available: data_url.present?,
      meta: public_sticker_metadata(metadata.presence || sticker_metadata(attachment)),
      created_at: sticker.created_at.to_i,
      updated_at: sticker.updated_at.to_i
    }
  end
end
