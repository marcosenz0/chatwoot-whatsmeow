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

    return enqueue_next(status) unless mark_processing(status)

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
    return status.account.whatsmeow_statuses.where(id: status.id) if status.publication_id.blank? || status.session_key.blank?

    status.account.whatsmeow_statuses.where(publication_id: status.publication_id, session_key: status.session_key)
  end

  def mark_processing(status)
    updated = update_deliveries(
      status,
      publication_state: WhatsmeowStatus.publication_states[:processing],
      publish_attempts: status.publish_attempts + 1,
      last_error: nil,
      next_attempt_at: nil
    )
    status.reload
    updated
  end

  def handle_publish_error(status, error)
    status.reload
    return enqueue_next(status) if status.publication_published?

    request_delivery_recovery(status)
    if status.publish_attempts < MAX_ATTEMPTS
      retry_at = Time.current + RETRY_INTERVAL
      return enqueue_next(status) unless update_deliveries(
        status,
        publication_state: WhatsmeowStatus.publication_states[:queued],
        last_error: error.message,
        next_attempt_at: retry_at
      )
      self.class.set(wait: RETRY_INTERVAL).perform_later(status.id)
    else
      return enqueue_next(status) unless mark_failed(status, error)

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

    request_delivery_recovery(status)
    attempts = status.publish_attempts
    attempts += 1 unless status.publication_processing?
    return fail_infrastructure_delivery(status, error, attempts) if attempts >= MAX_ATTEMPTS

    return enqueue_next(status) unless update_deliveries(
      status,
      publication_state: WhatsmeowStatus.publication_states[:queued],
      publish_attempts: attempts,
      last_error: error.message,
      next_attempt_at: Time.current + RETRY_INTERVAL
    )
    self.class.set(wait: RETRY_INTERVAL).perform_later(status.id)
  end

  def fail_infrastructure_delivery(status, error, attempts)
    return enqueue_next(status) unless update_deliveries(
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
    return enqueue_next(status) unless update_deliveries(status, next_attempt_at: retry_at)

    self.class.set(wait: wait_seconds.seconds).perform_later(status.id)
  end

  def update_deliveries(status, **attributes)
    WhatsmeowStatus.transaction do
      deliveries = delivery_scope(status).lock.to_a
      raise ActiveRecord::RecordNotFound if deliveries.empty?

      return false if deliveries.all?(&:publication_published?)

      deliveries.reject(&:publication_published?).each { |delivery| delivery.update!(attributes) }
      true
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

  def request_delivery_recovery(status)
    Whatsmeow::RecoverStatusDeliveryJob.perform_later(status.id)
  rescue StandardError => e
    Rails.logger.error("[Whatsmeow::PublishStatusJob] Failed to request Status recovery: #{e.message}")
  end
end
