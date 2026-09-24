class Whatsmeow::ChatReadService
  def initialize(inbox:, params:)
    @inbox = inbox
    @params = params.with_indifferent_access
  end

  def perform
    return if source_ids.empty?

    contact_inbox_ids = inbox.contact_inboxes.where(source_id: source_ids).select(:id)
    inbox.conversations.where(contact_inbox_id: contact_inbox_ids).find_each do |conversation|
      synchronize(conversation)
    end
  end

  private

  attr_reader :inbox, :params

  def source_ids
    [params[:chat], params[:phone_jid], params[:lid_jid]].compact_blank.uniq
  end

  def message_at(conversation)
    timestamp = params[:message_at].to_i
    return Time.zone.at(timestamp) if timestamp.positive?

    messages = conversation.messages
    messages = messages.where(source_id: params[:message_ids]) if params[:message_ids].present?
    messages.maximum(:created_at)
  end

  def synchronize(conversation)
    read_cursor = message_at(conversation)
    return if read_cursor.blank?

    changed = conversation.with_lock do
      next false if stale_event?(conversation)

      last_seen = read? ? [conversation.agent_last_seen_at, read_cursor].compact.max : unread_cutoff(conversation, read_cursor)
      next false if last_seen.blank?

      # The read cursor is an external device state; model update callbacks must
      # not publish a second conversation event or trigger unrelated workflows.
      # rubocop:disable Rails/SkipsModelValidations
      conversation.update_columns(read_attributes(conversation, last_seen))
      # rubocop:enable Rails/SkipsModelValidations
      true
    end
    return unless changed

    notify(conversation)
  end

  def stale_event?(conversation)
    event_at = params[:timestamp].to_i
    event_at.positive? && event_at <= conversation.additional_attributes['whatsmeow_read_event_at'].to_i
  end

  def read?
    ActiveModel::Type::Boolean.new.cast(params[:read])
  end

  def read_attributes(conversation, last_seen)
    attributes = { agent_last_seen_at: last_seen, assignee_last_seen_at: last_seen }
    event_at = params[:timestamp].to_i
    return attributes unless event_at.positive?

    attributes.merge(additional_attributes: conversation.additional_attributes.merge('whatsmeow_read_event_at' => event_at))
  end

  def notify(conversation)
    conversation.dispatch_conversation_updated_event
    Conversations::UnreadCounts::Notifier.new(conversation).perform
    Conversations::UnreadCounts::FilteredCountInvalidator.new(conversation.account).conversation_changed!
  end

  def unread_cutoff(conversation, read_cursor)
    latest_incoming = conversation.messages.incoming.where('created_at <= ?', read_cursor).order(created_at: :desc).first
    latest_incoming&.created_at&.-(1.second)
  end
end
