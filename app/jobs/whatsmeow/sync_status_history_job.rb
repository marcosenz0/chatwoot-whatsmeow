class Whatsmeow::SyncStatusHistoryJob < ApplicationJob
  self.queue_adapter = :sidekiq unless Rails.env.test?

  queue_as :default

  def perform(inbox_id)
    inbox = Inbox.find_by(id: inbox_id)
    return unless inbox&.channel_type == 'Channel::Whatsmeow' && inbox.channel.status == 'connected'

    Whatsmeow::StatusHistorySyncService.new(inbox: inbox).perform
  end
end
