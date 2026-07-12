class Whatsmeow::OpenConversationMergeService
  pattr_initialize [:inbox!, :contact!, :contact_inbox!, :source_ids!]

  def perform
    conversations = open_identity_conversations
    return if conversations.size < 2

    target = canonical_conversation(conversations)
    conversations.reject { |conversation| conversation.id == target.id }.each do |source|
      merge_conversation(target, source)
    end
    target.reload
  end

  private

  def open_identity_conversations
    contact_inbox_ids = inbox.contact_inboxes.where(source_id: source_ids).select(:id)
    contact.conversations.where(inbox_id: inbox.id, contact_inbox_id: contact_inbox_ids)
           .where.not(status: :resolved).order(:created_at).to_a
  end

  def canonical_conversation(conversations)
    conversations.find { |conversation| conversation.contact_inbox_id == contact_inbox.id } || conversations.first
  end

  def merge_conversation(target, source)
    return if target.csat_survey_response.present? && source.csat_survey_response.present?

    merge_labels(target, source)
    merge_participants(target, source)
    merge_mentions(target, source)
    source.reporting_events.update_all(conversation_id: target.id)
    source.messages.update_all(conversation_id: target.id)
    source.csat_survey_response&.update!(conversation: target)
    update_activity(target, source)
    source.destroy!
  end

  def merge_labels(target, source)
    target.update!(label_list: (target.label_list + source.label_list).uniq)
  end

  def merge_participants(target, source)
    source.conversation_participants.find_each do |participant|
      if target.conversation_participants.exists?(user_id: participant.user_id)
        participant.destroy!
      else
        participant.update!(conversation: target)
      end
    end
  end

  def merge_mentions(target, source)
    source.mentions.find_each do |mention|
      existing_mention = target.mentions.find_by(user_id: mention.user_id)
      if existing_mention
        existing_mention.update!(mentioned_at: [existing_mention.mentioned_at, mention.mentioned_at].max)
        mention.destroy!
      else
        mention.update!(conversation: target)
      end
    end
  end

  def update_activity(target, source)
    target.update!(last_activity_at: [target.last_activity_at, source.last_activity_at].compact.max)
  end
end
