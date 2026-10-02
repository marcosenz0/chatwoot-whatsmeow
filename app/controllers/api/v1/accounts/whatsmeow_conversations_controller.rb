class Api::V1::Accounts::WhatsmeowConversationsController < Api::V1::Accounts::BaseController
  def read_all
    scope = Current.account.conversations.where(inbox_id: policy_scope(Current.account.inboxes).where(channel_type: 'Channel::Whatsmeow').select(:id))
    scope = scope.where(inbox_id: params[:inbox_id]) if params[:inbox_id].present?
    seen_at = Time.current
    scope.find_each do |conversation|
      mark_read(conversation, seen_at) if ConversationPolicy.new(pundit_user, conversation).show?
    end
    Conversations::UnreadCounts::FilteredCountInvalidator.new(Current.account).conversation_changed!
    head :ok
  end

  def export
    conversation = Current.account.conversations.find_by!(display_id: params[:id])
    authorize conversation, :show?
    raise ActiveRecord::RecordNotFound unless conversation.inbox.channel_type == 'Channel::Whatsmeow'

    lines = conversation.messages.where(private: false).includes(:sender, :attachments).reorder(:created_at, :id).map do |message|
      export_line(message, conversation)
    end
    send_data lines.join("\n\n"), type: 'text/plain; charset=utf-8', filename: "conversation-#{conversation.display_id}.txt"
  end

  private

  def mark_read(conversation, seen_at)
    updates = { agent_last_seen_at: seen_at }
    updates[:assignee_last_seen_at] = seen_at if conversation.assignee_id == Current.user.id
    # Cursor updates follow the regular conversation read action and avoid running unrelated update callbacks.
    conversation.update_columns(updates) # rubocop:disable Rails/SkipsModelValidations
    Conversations::UnreadCounts::Notifier.new(conversation).perform
  end

  def export_line(message, conversation)
    sender = message.content_attributes['participant_name'].presence || message.sender&.name || conversation.contact.name
    attachments = message.attachments.filter_map { |attachment| attachment.push_event_data[:data_url] }
    "[#{message.created_at.iso8601}] #{sender}: #{[message.content, *attachments].compact.join("\n")}"
  end
end
