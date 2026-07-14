class Whatsmeow::RecoverStatusDeliveryJob < ApplicationJob
  self.queue_adapter = :sidekiq unless Rails.env.test?

  queue_as :default

  COOLDOWN = 2.minutes

  def perform(status_id)
    status = WhatsmeowStatus.find_by(id: status_id)
    return unless recoverable?(status)
    return unless acquire_recovery_slot(status)

    Whatsmeow::SessionClient.new(inbox: status.inbox).recover_status(message_id: status.source_id)
  rescue Whatsmeow::SessionClient::Error => e
    Rails.logger.info("[Whatsmeow::RecoverStatusDeliveryJob] Could not recover Status #{status_id}: #{e.message}")
  end

  private

  def recoverable?(status)
    status.present? &&
      status.from_me? &&
      status.source_id.present? &&
      status.expires_at > Time.current &&
      !status.publication_published? &&
      status.inbox.channel_type == 'Channel::Whatsmeow' &&
      status.inbox.channel.status == 'connected'
  end

  def acquire_recovery_slot(status)
    ::Redis::Alfred.set(
      "whatsmeow:status-recovery:#{status.inbox_id}:#{status.source_id}",
      '1',
      nx: true,
      ex: COOLDOWN.to_i
    )
  end
end
