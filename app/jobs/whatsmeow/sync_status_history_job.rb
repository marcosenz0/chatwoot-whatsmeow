class Whatsmeow::SyncStatusHistoryJob < ApplicationJob
  self.queue_adapter = :sidekiq unless Rails.env.test?

  queue_as :default

  COOLDOWN = 1.minute

  def perform(inbox_id)
    inbox = Inbox.find_by(id: inbox_id)
    return unless inbox&.channel_type == 'Channel::Whatsmeow' && inbox.channel&.status == 'connected'
    return unless acquire_sync_slot(inbox.id)

    Whatsmeow::StatusHistorySyncService.new(inbox: inbox).perform
  end

  private

  def acquire_sync_slot(inbox_id)
    ::Redis::Alfred.set("whatsmeow:status-history-sync:#{inbox_id}", '1', nx: true, ex: COOLDOWN.to_i)
  end
end
