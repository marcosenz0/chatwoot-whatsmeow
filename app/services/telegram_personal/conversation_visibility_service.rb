class TelegramPersonal::ConversationVisibilityService
  def self.perform(relation)
    %w[group channel].reduce(relation) do |visible, kind|
      channels = Channel::TelegramPersonal.where("hide_#{kind.pluralize}" => true).select(:id)
      inboxes = Inbox.where(channel_type: 'Channel::TelegramPersonal', channel_id: channels)
      hidden = relation.where(inbox_id: inboxes).where("conversations.additional_attributes ->> ? = 'true'", "telegram_#{kind}").select(:id)
      visible.where.not(id: hidden)
    end
  end
end
