class TelegramPersonal::IncomingEventService
  include FileTypeHelper
  pattr_initialize [:inbox!, :payload!]

  def perform
    case payload.fetch('event')
    when 'session' then inbox.channel.update!(payload.slice('status', 'telegram_user_id', 'username'))
    when 'message' then create_message
    when 'edit' then edit_message
    when 'delete' then delete_messages
    when 'read' then read_messages
    else raise ArgumentError, 'Unknown Telegram account event'
    end
  end

  private

  def create_message
    return if merge_outgoing_echo
    return if inbox.messages.exists?(source_id: payload.fetch('source_id'))
    return if ignored_chat?

    message = conversation.messages.build(message_attributes)
    payload.fetch('attachments', []).each { |attachment| attach_file(message, attachment) }
    attach_location(message) if payload['location']
    message.save!
  end

  def merge_outgoing_echo
    return false if payload['chatwoot_message_id'].blank?

    message = inbox.messages.outgoing.where(private: false).find(payload['chatwoot_message_id'])
    message.update!(source_id: payload.fetch('source_id'), status: :sent) if message.source_id.blank?
    true
  end

  def ignored_chat?
    (inbox.channel.ignore_groups && payload['group']) || (inbox.channel.ignore_channels && payload['channel'])
  end

  def contact_inbox
    @contact_inbox ||= ContactInboxWithContactBuilder.new(
      inbox: inbox, source_id: payload.fetch('chat_id').to_s,
      contact_attributes: { name: payload.fetch('chat_name'), additional_attributes: payload.fetch('contact_attributes', {}) }
    ).perform
  end

  def conversation
    @conversation ||= contact_inbox.conversations.order(:id).last || contact_inbox.conversations.create!(
      account_id: inbox.account_id, inbox_id: inbox.id, contact_id: contact_inbox.contact_id,
      additional_attributes: payload.slice('chat_id', 'group', 'channel').transform_keys { |key| "telegram_#{key}" }
    )
  end

  def message_attributes
    {
      account_id: inbox.account_id, inbox_id: inbox.id, source_id: payload.fetch('source_id'),
      content: payload['content'], message_type: payload['outgoing'] ? :outgoing : :incoming,
      sender: payload['outgoing'] ? nil : contact_inbox.contact,
      created_at: Time.zone.at(payload.fetch('date')),
      content_attributes: payload.fetch('content_attributes', {})
    }
  end

  def attach_file(message, attachment)
    data = TelegramPersonal::SessionClient.new(inbox: inbox).download_media(attachment.fetch('id'))
    message.attachments.build(
      account_id: inbox.account_id, file_type: file_type(attachment.fetch('content_type')),
      file: { io: StringIO.new(data), filename: attachment.fetch('filename'), content_type: attachment.fetch('content_type') }
    )
  end

  def attach_location(message)
    location = payload.fetch('location')
    message.attachments.build(account_id: inbox.account_id, file_type: :location,
                              coordinates_lat: location.fetch('lat'), coordinates_long: location.fetch('long'))
  end

  def edit_message
    message = inbox.messages.find_by(source_id: payload.fetch('source_id'))
    return unless message
    return if message.content_attributes['telegram_edited_at'].to_i >= payload.fetch('date')

    message.update!(content: payload['content'], content_attributes: message.content_attributes.merge('telegram_edited_at' => payload['date']))
  end

  def delete_messages
    inbox.messages.where(source_id: payload.fetch('source_ids')).find_each do |message|
      message.update!(content_attributes: message.content_attributes.merge('deleted' => true, 'deleted_on_telegram' => true))
    end
  end

  def read_messages
    contact_inbox = inbox.contact_inboxes.find_by(source_id: payload.fetch('chat_id').to_s)
    return unless contact_inbox

    contact_inbox.conversations.each do |conversation|
      conversation.messages.outgoing.where(private: false).find_each do |message|
        next unless message.source_id.present? && message.source_id.split(':').last.to_i <= payload.fetch('max_id')

        message.update!(status: :read)
      end
    end
  end
end
