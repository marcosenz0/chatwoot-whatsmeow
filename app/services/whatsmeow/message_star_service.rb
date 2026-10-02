class Whatsmeow::MessageStarService
  def self.apply_incoming(inbox:, params:)
    data = params.with_indifferent_access
    new(inbox: inbox, chat_jid: data.fetch(:chat), source_id: data.fetch(:message_id)).persist(
      starred: data.fetch(:starred), occurred_at: Time.zone.at(data.fetch(:timestamp).to_i)
    )
  end

  def self.attach(message)
    return if message.source_id.blank?

    chat_jid = Whatsmeow::ConversationTargetResolver.new(conversation: message.conversation).perform
    star = WhatsmeowMessageStar.find_by(inbox_id: message.inbox_id, chat_jid: chat_jid, source_id: message.source_id)
    return unless star

    star.with_lock do
      star.update!(message: message)
      message.with_lock { message.update!(content_attributes: message.content_attributes.merge('whatsmeow_starred' => star.starred)) }
    end
  end

  def initialize(inbox:, chat_jid:, source_id:)
    @inbox = inbox
    @chat_jid = chat_jid
    @source_id = source_id
  end

  def perform(message:, starred:)
    if message.private? || message.source_id.blank? || !(message.incoming? || message.outgoing?)
      raise ArgumentError, 'Only public WhatsApp Direct messages can be starred'
    end
    raise ArgumentError, 'Only WhatsApp Direct messages can be starred' unless @inbox.channel_type == 'Channel::Whatsmeow'
    raise ArgumentError, 'starred must be a boolean' unless [true, false].include?(starred)

    Whatsmeow::SessionClient.new(inbox: @inbox).star_message(
      chat: @chat_jid, message_id: @source_id, from_me: message.outgoing?,
      sender: message.content_attributes['participant_jid'], starred: starred
    )
    persist(starred: starred, occurred_at: Time.current, message: message)
    message.reload
  end

  def persist(starred:, occurred_at:, message: nil)
    record = WhatsmeowMessageStar.create_or_find_by!(inbox: @inbox, chat_jid: @chat_jid, source_id: @source_id) do |star|
      star.starred = starred
      star.occurred_at = occurred_at
    end
    record.with_lock do
      return record if record.occurred_at > occurred_at

      message ||= @inbox.messages.joins(conversation: :contact_inbox)
                        .find_by(source_id: @source_id, contact_inboxes: { source_id: @chat_jid })
      record.update!(starred: starred, occurred_at: occurred_at, message: message)
      message&.with_lock { message.update!(content_attributes: message.content_attributes.merge('whatsmeow_starred' => starred)) }
    end
    record
  end
end
