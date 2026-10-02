class MessageFinder
  MESSAGE_ID_MAX = 2_147_483_647

  def initialize(conversation, params)
    @conversation = conversation
    @params = params
  end

  def perform
    current_messages
  end

  private

  def conversation_messages
    @conversation.messages.includes(:attachments, :sender, sender: { avatar_attachment: [:blob] })
  end

  def messages
    return conversation_messages.where('content ILIKE ?', "%#{ActiveRecord::Base.sanitize_sql_like(@params[:q])}%") if @params[:q].present?

    if @params[:group_changes].present?
      return conversation_messages.where("(content_attributes #>> '{}')::jsonb ->> 'whatsmeow_group_change' = 'true'")
    end
    return conversation_messages if @params[:filter_internal_messages].blank?

    conversation_messages.where.not('private = ? OR message_type = ?', true, 2)
  end

  def current_messages
    after_id, before_id, around_id = @params.values_at(:after, :before, :around)
    return messages.none if oversized_message_id?(after_id)
    return messages_around(normalized_message_id(around_id)) if around_id.present?

    if after_id.present? && before_id.present?
      messages_between(normalized_message_id(after_id), before_id.to_i)
    elsif before_id.present?
      messages_before(before_id.to_i)
    elsif after_id.present?
      messages_after(normalized_message_id(after_id))
    else
      messages_latest
    end
  end

  def messages_around(message_id)
    anchor = messages.find(message_id)
    earlier = messages.reorder(created_at: :desc, id: :desc)
                      .where('(messages.created_at, messages.id) < (?, ?)', anchor.created_at, anchor.id).limit(20).reverse
    later = messages.reorder(created_at: :asc, id: :asc)
                    .where('(messages.created_at, messages.id) >= (?, ?)', anchor.created_at, anchor.id).limit(21).to_a
    earlier + later
  end

  def messages_after(after_id)
    messages.reorder('created_at asc').where('id > ?', after_id).limit(100)
  end

  def messages_before(before_id)
    return messages_latest if oversized_message_id?(before_id)

    before_id = normalized_message_id(before_id)
    if @conversation.inbox.channel_type == 'Channel::Whatsmeow'
      anchor = messages.find_by(id: before_id)
      return [] unless anchor

      return messages.reorder(created_at: :desc, id: :desc)
                     .where('(messages.created_at, messages.id) < (?, ?)', anchor.created_at, anchor.id).limit(20).reverse
    end

    messages.reorder('created_at desc').where('id < ?', before_id).limit(20).reverse
  end

  def messages_between(after_id, before_id)
    message_scope = messages.reorder('created_at asc').where('id >= ?', after_id)
    message_scope = message_scope.where('id < ?', normalized_message_id(before_id)) unless oversized_message_id?(before_id)
    message_scope.limit(1000)
  end

  def messages_latest
    messages.reorder(created_at: :desc, id: :desc).limit(20).reverse
  end

  def normalized_message_id(value)
    value.to_i.clamp(0, MESSAGE_ID_MAX)
  end

  def oversized_message_id?(value)
    value.to_i > MESSAGE_ID_MAX
  end
end

MessageFinder.prepend_mod_with('MessageFinder')
