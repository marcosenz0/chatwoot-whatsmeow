class Whatsmeow::PurgeExpiredStatusesJob < ApplicationJob
  queue_as :housekeeping

  def perform
    WhatsmeowStatus.where(expires_at: ..Time.current).find_each(&:destroy!)
  end
end
