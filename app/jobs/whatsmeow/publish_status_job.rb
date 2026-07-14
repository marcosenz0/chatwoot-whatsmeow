class Whatsmeow::PublishStatusJob < ApplicationJob
  self.queue_adapter = :sidekiq unless Rails.env.test?

  queue_as :default

  MAX_ATTEMPTS = 3
  RETRY_INTERVAL = 60.seconds

  def perform(status_id)
    status = WhatsmeowStatus.find_by(id: status_id)
    return if status.blank? || status.expires_at <= Time.current
    return enqueue_next(status) if status.publication_published? || status.publication_failed?

    lock = Whatsmeow::StatusPublishLock.new(status: status)
    wait_seconds = lock.acquire
    return reschedule(status, wait_seconds) if wait_seconds.positive?

    mark_processing(status)
    Whatsmeow::StatusPublisher.new(status: status).perform
    finish_lock(lock)
    enqueue_next(status)
  rescue Whatsmeow::SessionClient::Error => e
    finish_lock(lock)
    handle_publish_error(status, e)
  rescue StandardError => e
    finish_lock(lock)
    handle_infrastructure_error(status, e)
  end

  private

  def delivery_scope(status)
    status.account.whatsmeow_statuses.where(publication_id: status.publication_id, session_key: status.session_key)
  end

  def mark_processing(status)
    update_deliveries(
      status,
      publication_state: WhatsmeowStatus.publication_states[:processing],
      publish_attempts: status.publish_attempts + 1,
      last_error: nil,
      next_attempt_at: nil
    )
    status.reload
  end

  def handle_publish_error(status, error)
    status.reload
    if status.publish_attempts < MAX_ATTEMPTS
      retry_at = Time.current + RETRY_INTERVAL
      update_deliveries(
        status,
        publication_state: WhatsmeowStatus.publication_states[:queued],
        last_error: error.message,
        next_attempt_at: retry_at
      )
      self.class.set(wait: RETRY_INTERVAL).perform_later(status.id)
    else
      mark_failed(status, error)
      enqueue_next(status)
    end
  end

  def mark_failed(status, error)
    update_deliveries(
      status,
      publication_state: WhatsmeowStatus.publication_states[:failed],
      last_error: error.message,
      next_attempt_at: nil
    )
  end

  def handle_infrastructure_error(status, error)
    status.reload
    return enqueue_next(status) if status.publication_published?

    attempts = status.publish_attempts
    attempts += 1 unless status.publication_processing?
    return fail_infrastructure_delivery(status, error, attempts) if attempts >= MAX_ATTEMPTS

    update_deliveries(
      status,
      publication_state: WhatsmeowStatus.publication_states[:queued],
      publish_attempts: attempts,
      last_error: error.message,
      next_attempt_at: Time.current + RETRY_INTERVAL
    )
    self.class.set(wait: RETRY_INTERVAL).perform_later(status.id)
  end

  def fail_infrastructure_delivery(status, error, attempts)
    update_deliveries(
      status,
      publication_state: WhatsmeowStatus.publication_states[:failed],
      publish_attempts: attempts,
      last_error: error.message,
      next_attempt_at: nil
    )
    enqueue_next(status)
  end

  def reschedule(status, wait_seconds)
    retry_at = Time.current + wait_seconds.seconds
    update_deliveries(status, next_attempt_at: retry_at)
    self.class.set(wait: wait_seconds.seconds).perform_later(status.id)
  end

  def update_deliveries(status, **attributes)
    WhatsmeowStatus.transaction do
      deliveries = delivery_scope(status).lock.to_a
      raise ActiveRecord::RecordNotFound if deliveries.empty?

      deliveries.each { |delivery| delivery.update!(attributes) }
    end
  end

  def enqueue_next(status)
    next_status = status.account.whatsmeow_statuses
                        .where(publication_id: status.publication_id, publication_state: :queued)
                        .where('publication_position > ?', status.publication_position)
                        .order(:publication_position, :id)
                        .first
    self.class.perform_later(next_status.id) if next_status.present?
  end

  def finish_lock(lock)
    lock&.finish
  rescue StandardError => e
    Rails.logger.error("[Whatsmeow::PublishStatusJob] Failed to finish publish lock: #{e.message}")
  end
end
