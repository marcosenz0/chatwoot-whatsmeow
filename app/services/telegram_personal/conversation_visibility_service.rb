class TelegramPersonal::ConversationVisibilityService
  def self.perform(relation)
    hidden_groups = Inbox.where(channel_type: 'Channel::TelegramPersonal', channel_id: Channel::TelegramPersonal.where(hide_groups: true).select(:id))
    hidden_channels = Inbox.where(channel_type: 'Channel::TelegramPersonal', channel_id: Channel::TelegramPersonal.where(hide_channels: true).select(:id))
    relation.where.not(id: relation.where(inbox_id: hidden_groups).where("conversations.additional_attributes ->> 'telegram_group' = 'true'").select(:id))
            .where.not(id: relation.where(inbox_id: hidden_channels).where("conversations.additional_attributes ->> 'telegram_channel' = 'true'").select(:id))
  end
end
