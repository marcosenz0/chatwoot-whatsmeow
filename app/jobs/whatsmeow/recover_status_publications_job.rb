class Whatsmeow::RecoverStatusPublicationsJob < ApplicationJob
  self.queue_adapter = :sidekiq unless Rails.env.test?

  queue_as :default

  LEASE_DURATION = 2.minutes
  STALE_AFTER = Whatsmeow::StatusPublishLock::OPERATION_TTL + 30.seconds

  def perform
    recover_stale_deliveries
    eligible_publications.each { |account_id, publication_id| enqueue_publication(account_id, publication_id) }
  end

  private

  def recover_stale_deliveries
    stale_delivery_keys.each do |account_id, publication_id, session_key|
      recover_stale_delivery(account_id, publication_id, session_key)
    end
  end

  def stale_delivery_keys
    WhatsmeowStatus
      .where(publication_state: :processing)
      .where('updated_at < ?', STALE_AFTER.ago)
      .where.not(publication_id: nil)
      .distinct
      .pluck(:account_id, :publication_id, :session_key)
  end

  def recover_stale_delivery(account_id, publication_id, session_key)
    WhatsmeowStatus.transaction do
      statuses = delivery_scope(account_id, publication_id, session_key).lock.to_a
      next if statuses.blank? || statuses.any? { |status| status.updated_at >= STALE_AFTER.ago }

      statuses.select(&:publication_processing?).each do |status|
        status.update!(publication_state: :queued, next_attempt_at: Time.current)
      end
    end
  end

  def eligible_publications
    WhatsmeowStatus.active
                   .where(publication_state: :queued)
                   .where('next_attempt_at IS NULL OR next_attempt_at <= ?', Time.current)
                   .where.not(publication_id: nil)
                   .distinct
                   .pluck(:account_id, :publication_id)
  end

  def enqueue_publication(account_id, publication_id)
    status_id = lease_next_delivery(account_id, publication_id)
    Whatsmeow::PublishStatusJob.perform_later(status_id) if status_id.present?
  rescue StandardError => e
    Rails.logger.error("[Whatsmeow::RecoverStatusPublicationsJob] Failed to recover #{publication_id}: #{e.message}")
  end

  def lease_next_delivery(account_id, publication_id)
    status_id = nil
    WhatsmeowStatus.transaction do
      status_id = lease_current_delivery(account_id, publication_id)
    end
    status_id
  end

  def lease_current_delivery(account_id, publication_id)
    statuses = publication_scope(account_id, publication_id).active.order(:publication_position, :id).lock.to_a
    current = current_delivery(statuses)
    return unless leaseable?(current)

    leader = current.select(&:publication_queued?).min_by(&:id)
    return if leader.blank?

    current.each { |status| status.update!(next_attempt_at: LEASE_DURATION.from_now) }
    leader.id
  end

  def leaseable?(statuses)
    statuses.present? && statuses.none?(&:publication_processing?) && statuses.none? { |status| retry_scheduled?(status) }
  end

  def current_delivery(statuses)
    pending = statuses.reject do |status|
      status.publication_published? ||
        status.publication_failed? ||
        status.publication_deleting? ||
        status.publication_delete_failed?
    end
    position = pending.filter_map(&:publication_position).min
    pending.select { |status| status.publication_position == position }
  end

  def retry_scheduled?(status)
    status.next_attempt_at.present? && status.next_attempt_at > Time.current
  end

  def publication_scope(account_id, publication_id)
    WhatsmeowStatus.where(account_id: account_id, publication_id: publication_id)
  end

  def delivery_scope(account_id, publication_id, session_key)
    publication_scope(account_id, publication_id).where(session_key: session_key)
  end
end
