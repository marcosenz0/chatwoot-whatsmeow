class MarcosxAi::ResourceHistory
  def self.for(resources, conversation)
    return {} unless conversation && resources.present?

    # Stay within the same contact and inbox; cross-channel context still requires operator approval.
    conversations = conversation.account.conversations.where(contact_id: conversation.contact_id, inbox_id: conversation.inbox_id)
    scope = MarcosxAi::ConversationContext.public_history(conversation).unscope(where: :conversation_id)
                                          .where(account_id: conversation.account_id, conversation_id: conversations.select(:id)).outgoing
    checksums = resources.filter_map { |resource| resource.file.checksum if resource.file.attached? }.uniq
    attachments = Attachment.where(message_id: scope.select(:id)).joins(file_attachment: :blob)
                            .where(active_storage_blobs: { checksum: checksums }).pluck(:message_id, 'active_storage_blobs.checksum')
    messages = scope.where("additional_attributes ->> 'marcosx_ai_resource_id' IN (?) OR messages.id IN (?)",
                           resources.map { |resource| resource.id.to_s }, attachments.map(&:first)).order(:created_at, :id).to_a
    resources.to_h do |resource|
      matching_ids = if resource.file.attached?
                       attachments.filter_map { |message_id, checksum| message_id if checksum == resource.file.checksum }
                     else
                       messages.filter_map { |message| message.id if message.additional_attributes['marcosx_ai_resource_id'] == resource.id }
                     end
      attempts = messages.select { |message| matching_ids.include?(message.id) }
      last = attempts.last
      sent = attempts.reject(&:failed?)
      [resource.id, { sent_count: sent.size, confirmed_count: sent.count { |message| message.delivered? || message.read? },
                      failed_count: attempts.count(&:failed?), last_message_id: last&.id, last_status: last&.status,
                      last_sent_at: sent.last&.created_at&.iso8601, last_attempt_at: last&.created_at&.iso8601 }]
    end
  end
end
