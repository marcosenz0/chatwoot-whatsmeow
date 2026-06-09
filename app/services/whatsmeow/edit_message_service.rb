class Whatsmeow::EditMessageService
  def self.apply_incoming(inbox:, params:)
    new(inbox: inbox, params: params).apply_incoming
  end

  def initialize(inbox:, params:)
    @inbox = inbox
    @params = params&.with_indifferent_access
  end

  def apply_incoming
    return if @params.blank?

    @message = @inbox.messages.find_by(source_id: @params[:message_id])
    return if @message.blank?

    edited_content = @params[:edited_content].to_s
    return if edited_content.blank?

    @message.update!(
      content: edited_content,
      content_attributes: edited_content_attributes(edited_content)
    )
  end

  private

  def edited_content_attributes(edited_content)
    content_attributes.merge(
      'whatsmeow_edited' => true,
      'whatsmeow_original_content' => original_content,
      'whatsmeow_edited_content' => edited_content,
      'whatsmeow_edited_from_me' => ActiveModel::Type::Boolean.new.cast(@params[:from_me]),
      'whatsmeow_edited_by' => incoming_sender,
      'whatsmeow_edited_at' => @params[:timestamp].presence || Time.current.to_i
    )
  end

  def original_content
    content_attributes['whatsmeow_original_content'].presence || @message.content.to_s
  end

  def incoming_sender
    return 'chatwoot' if ActiveModel::Type::Boolean.new.cast(@params[:from_me])

    @params[:sender].presence || @params[:sender_alt].presence || 'whatsapp'
  end

  def content_attributes
    @content_attributes ||= (@message.content_attributes || {}).stringify_keys
  end
end
