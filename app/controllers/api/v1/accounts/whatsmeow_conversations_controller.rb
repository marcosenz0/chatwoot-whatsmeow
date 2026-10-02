class Api::V1::Accounts::WhatsmeowConversationsController < Api::V1::Accounts::BaseController
  def read_all
    scope = Current.account.conversations.where(inbox_id: policy_scope(Current.account.inboxes).where(channel_type: 'Channel::Whatsmeow').select(:id))
    scope = scope.where(inbox_id: params[:inbox_id]) if params[:inbox_id].present?
    seen_at = Time.current
    scope.find_each do |conversation|
      next unless ConversationPolicy.new(pundit_user, conversation).show?

      updates = { agent_last_seen_at: seen_at }
      updates[:assignee_last_seen_at] = seen_at if conversation.assignee_id == Current.user.id
      conversation.update_columns(updates)
      Conversations::UnreadCounts::Notifier.new(conversation).perform
    end
    Conversations::UnreadCounts::FilteredCountInvalidator.new(Current.account).conversation_changed!
    head :ok
  end

  def export
    conversation = Current.account.conversations.find_by!(display_id: params[:id])
    authorize conversation, :show?
    raise ActiveRecord::RecordNotFound unless conversation.inbox.channel_type == 'Channel::Whatsmeow'

    lines = conversation.messages.where(private: false).includes(:sender, :attachments).reorder(:created_at, :id).map do |message|
      sender = message.content_attributes['participant_name'].presence || message.sender&.name || conversation.contact.name
      attachments = message.attachments.map { |attachment| attachment.push_event_data[:data_url] }.compact
      "[#{message.created_at.iso8601}] #{sender}: #{[message.content, *attachments].compact.join("\n")}"
    end
    send_data lines.join("\n\n"), type: 'text/plain; charset=utf-8', filename: "conversation-#{conversation.display_id}.txt"
  end
end
