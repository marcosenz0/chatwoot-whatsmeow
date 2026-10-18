class MarcosxAi::PendingConversations
  def initialize(assistant:, user:)
    @assistant = assistant
    @user = user
  end

  def scope
    inbox_ids = @assistant.inboxes.select(:id)
    overrides = @assistant.conversation_states.where("metadata ->> 'conversation_override' = 'true'").select(:conversation_id)
    conversations = @assistant.account.conversations.where(inbox_id: inbox_ids)
    conversations = conversations.or(@assistant.account.conversations.where(id: overrides))
    conversations = Conversations::PermissionFilterService.new(conversations, @user, @assistant.account).perform
    attributes_sql = MarcosxAi::ConversationContext::CONTENT_ATTRIBUTES_SQL
    latest = Message.where(private: false, message_type: [:incoming, :outgoing])
                    .where('messages.conversation_id = conversations.id').where.not(content_type: 'voice_call')
                    .where("COALESCE(additional_attributes ->> 'marcosx_ai_operational', 'false') != 'true'")
                    .where("COALESCE(#{attributes_sql} ->> 'historical', 'false') != 'true'")
                    .where("COALESCE(#{attributes_sql} ->> 'deleted', 'false') != 'true'")
                    .where("COALESCE(#{attributes_sql} ->> 'whatsmeow_deleted', 'false') != 'true'")
                    .where("COALESCE(#{attributes_sql} ->> 'is_unsupported', 'false') != 'true'")
                    .where('COALESCE(content, ?) NOT LIKE ?', '', "#{MarcosxAi::AlertService::NOTICE_PREFIX}%")
                    .reorder(id: :desc).limit(1).select(:id, :message_type, :created_at)
    conversations = conversations.joins(:contact, :inbox).left_joins(:marcosx_ai_conversation_state)
                                 .joins("JOIN LATERAL (#{latest.to_sql}) pending_message ON true")
                                 .where(contacts: { blocked: false }, status: [:open, :pending])
                                 .where('pending_message.message_type = ?', Message.message_types[:incoming])
    states = 'marcosx_ai_conversation_states'
    conversations = conversations.where("#{states}.id IS NULL OR (#{states}.status NOT IN ('handoff', 'awaiting_human') AND " \
                                        "COALESCE(#{states}.metadata ->> 'processing', 'false') != 'true' AND " \
                                        "COALESCE((#{states}.metadata ->> 'last_processed_trigger_id')::bigint, 0) < pending_message.id)")
                                 .where("COALESCE(#{states}.metadata ->> 'conversation_override', 'false') != 'true' OR #{states}.assistant_id = ?",
                                        @assistant.id)
                                 .where("inboxes.channel_type NOT IN ('Channel::Instagram', 'Channel::FacebookPage') OR " \
                                        'pending_message.created_at > ?',
                                        24.hours.ago)
    unless @assistant.feature_enabled?(:respond_to_groups)
      conversations = conversations.where("COALESCE(conversations.additional_attributes ->> 'whatsmeow_group', 'false') = 'false' AND " \
                                          "COALESCE(conversations.additional_attributes ->> 'telegram_group', 'false') = 'false' AND " \
                                          "COALESCE(contacts.additional_attributes ->> 'whatsmeow_group', 'false') = 'false' AND " \
                                          "COALESCE(conversations.additional_attributes ->> 'chat_type', '') " \
                                          "NOT IN ('group', 'supergroup', 'channel')")
    end
    conversations.includes(:contact, :inbox, :marcosx_ai_conversation_state).order(last_activity_at: :desc, id: :desc)
  end

  def latest(conversation)
    attributes_sql = MarcosxAi::ConversationContext::CONTENT_ATTRIBUTES_SQL
    MarcosxAi::ConversationContext.public_history(conversation).where("COALESCE(#{attributes_sql} ->> 'historical', 'false') != 'true'")
                                  .where("COALESCE(#{attributes_sql} ->> 'is_unsupported', 'false') != 'true'").reorder(id: :desc).first
  end

  def eligible?(conversation, trigger_id: nil)
    conversation.reload
    return false unless scope.where(id: conversation.id).exists? && @assistant.accepts_conversation?(conversation)
    return false unless conversation.marcosx_ai_assistant&.id == @assistant.id

    state = conversation.marcosx_ai_conversation_state
    return false if state && (state.status.in?(%w[handoff awaiting_human]) || state.metadata['processing'] == true)

    message = latest(conversation)
    message&.incoming? && (!trigger_id || message.id == trigger_id) && state&.metadata&.fetch('last_processed_trigger_id', 0).to_i < message.id
  end

  def data(conversation)
    message = latest(conversation)
    { id: conversation.display_id, name: conversation.contact.name, avatar_url: conversation.contact.avatar_url,
      inbox: conversation.inbox.name, sent_at: message.created_at.iso8601,
      message: message.content.presence || message.attachments.first&.file_type || '',
      paused: conversation.marcosx_ai_conversation_state&.status != 'active' }
  end
end
