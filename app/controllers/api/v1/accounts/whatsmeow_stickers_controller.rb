class Api::V1::Accounts::WhatsmeowStickersController < Api::V1::Accounts::BaseController
  before_action :set_sticker, only: [:destroy, :send]

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
    sticker.metadata = sticker_metadata(attachment)
    sticker.save!

    render json: { payload: sticker_payload(sticker) }
  end

  def destroy
    authorize @sticker

    @sticker.destroy!
    head :ok
  end

  def send
    authorize @sticker

    conversation = Current.account.conversations.find(sticker_params[:conversation_id])
    authorize conversation, :show?

    message = build_sticker_message(conversation, @sticker.attachment)
    render json: { payload: message.push_event_data }
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

  def build_sticker_message(conversation, source_attachment)
    message = conversation.messages.build(
      account: Current.account,
      inbox: conversation.inbox,
      message_type: :outgoing,
      status: :sent,
      sender: current_user,
      content_attributes: { whatsmeow_sticker: true }
    )

    attachment = message.attachments.build(
      account: Current.account,
      file_type: :image,
      meta: sticker_metadata(source_attachment)
    )
    attachment.file.attach(source_attachment.file.blob)
    message.save!
    message
  end

  def sticker_payload(sticker)
    attachment = sticker.attachment

    {
      id: sticker.id,
      attachment_id: attachment.id,
      file_name: attachment.file.attached? ? attachment.file.filename.to_s : '',
      content_type: attachment.file.attached? ? attachment.file.content_type : '',
      data_url: attachment.file_url,
      thumb_url: attachment.thumb_url,
      meta: sticker.metadata.presence || sticker_metadata(attachment),
      created_at: sticker.created_at.to_i,
      updated_at: sticker.updated_at.to_i
    }
  end
end
