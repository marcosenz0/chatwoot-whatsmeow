class Whatsmeow::AttachmentRetentionScheduler
  CACHE_KEY = 'whatsmeow:attachment_retention:last_enqueued'
  INTERVAL = 24.hours

  def self.maybe_enqueue
    new.maybe_enqueue
  end

  def maybe_enqueue
    return if retention_disabled?
    return unless daily_lock_acquired?

    Whatsmeow::PurgeOldAttachmentsJob.perform_later
  rescue StandardError => e
    Rails.logger.warn("Whatsmeow attachment retention could not be scheduled: #{e.message}")
  end

  private

  def retention_disabled?
    ENV.fetch(
      'WHATSMEOW_ATTACHMENT_RETENTION_DAYS',
      Whatsmeow::PurgeOldAttachmentsJob::DEFAULT_RETENTION_DAYS
    ).to_i <= 0
  end

  def daily_lock_acquired?
    Rails.cache.write(CACHE_KEY, Time.current.to_i, expires_in: INTERVAL, unless_exist: true)
  end
end
