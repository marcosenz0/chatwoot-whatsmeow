class Whatsmeow::DeleteStatusPublicationJob < ApplicationJob
  self.queue_adapter = :sidekiq unless Rails.env.test?

  queue_as :default

  def perform(status_id)
    status = WhatsmeowStatus.find_by(id: status_id)
    return if status.blank? || status.expires_at <= Time.current || !status.publication_deleting?

    lock = Whatsmeow::StatusPublishLock.new(status: status)
    wait_seconds = lock.acquire
    return reschedule(status, wait_seconds) if wait_seconds.positive?

    delete_remote_status(status) if remote_deletion_required?(status)
    remove_delivery(status)
    finish_lock(lock)
    enqueue_next(status)
  rescue Whatsmeow::SessionClient::Error => e
    finish_lock(lock)
    handle_deletion_error(status, e)
  rescue StandardError => e
    finish_lock(lock)
    handle_deletion_error(status, e)
  end

  private

  def delivery_scope(status)
    return WhatsmeowStatus.where(id: status.id) if status.publication_id.blank? || status.session_key.blank?

    WhatsmeowStatus.where(
      account_id: status.account_id,
      publication_id: status.publication_id,
      session_key: status.session_key
    )
  end

  def delete_remote_status(status)
    Whatsmeow::SessionClient.new(inbox: status.inbox).delete_status(status.source_id)
  end

  def remote_deletion_required?(status)
    metadata = status.metadata || {}
    return metadata['delete_requires_remote'] if metadata.key?('delete_requires_remote')

    status.publish_attempts.positive? || status.publication_published?
  end

  def remove_delivery(status)
    WhatsmeowStatus.transaction do
      delivery_scope(status).lock.find_each(&:destroy!)
    end
  end

  def handle_deletion_error(status, error)
    return if status.blank?

    update_deliveries(
      status,
      publication_state: WhatsmeowStatus.publication_states[:delete_failed],
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
      deleting_deliveries = deliveries.select(&:publication_deleting?)
      return false if deleting_deliveries.empty?

      deleting_deliveries.each { |delivery| delivery.update!(attributes) }
      true
    end
  end

  def enqueue_next(status)
    return if status.publication_id.blank? || status.publication_position.blank?

    next_status = WhatsmeowStatus
                  .where(
                    account_id: status.account_id,
                    publication_id: status.publication_id,
                    publication_state: :deleting
                  )
                  .where('publication_position > ?', status.publication_position)
                  .order(:publication_position, :id)
                  .first
    self.class.perform_later(next_status.id) if next_status.present?
  end

  def finish_lock(lock)
    lock&.finish
  rescue StandardError => e
    Rails.logger.error("[Whatsmeow::DeleteStatusPublicationJob] Failed to finish delete lock: #{e.message}")
  end
end
