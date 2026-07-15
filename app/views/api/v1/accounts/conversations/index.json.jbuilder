json.data do
  json.meta do
    json.mine_count @conversations_count[:mine_count]
    json.assigned_count @conversations_count[:assigned_count]
    json.unassigned_count @conversations_count[:unassigned_count]
    json.all_count @conversations_count[:all_count]
    json.group_count @conversations_count[:group_count]
  end
  json.payload do
    json.array! @conversations do |conversation|
      begin
        json.partial! 'api/v1/conversations/partials/conversation', formats: [:json], conversation: conversation
      rescue StandardError => e
        Rails.logger.error("Unable to serialize conversation #{conversation.id}: #{e.class}: #{e.message}")

        json.meta do
          json.sender do
            json.id conversation.contact_id
            json.name nil
            json.email nil
            json.phone_number nil
            json.thumbnail ''
            json.type 'contact'
          end
          json.channel conversation.inbox&.channel_type
          json.hmac_verified false
        end
        json.id conversation.display_id
        json.messages []
        json.account_id conversation.account_id
        json.inbox_id conversation.inbox_id
        json.labels conversation.cached_label_list_array
        json.status conversation.status
        json.created_at conversation.created_at.to_i
        json.updated_at conversation.updated_at.to_f
        json.timestamp conversation.last_activity_at.to_i
        json.unread_count 0
        json.last_activity_at conversation.last_activity_at.to_i
        json.priority conversation.priority
      end
    end
  end
end
