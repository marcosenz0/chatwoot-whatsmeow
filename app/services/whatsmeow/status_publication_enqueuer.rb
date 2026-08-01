class Whatsmeow::StatusPublicationEnqueuer
  pattr_initialize [:statuses!]

  def perform
    status = current_queued_status
    return if status.blank?

    wait_seconds = [status.next_attempt_at.to_i - Time.current.to_i, 0].max
    if wait_seconds.positive?
      Whatsmeow::PublishStatusJob.set(wait: wait_seconds.seconds).perform_later(status.id)
    else
      Whatsmeow::PublishStatusJob.perform_later(status.id)
    end
  end

  private

  def current_queued_status
    current = current_delivery
    return if current.any?(&:publication_processing?)

    current.select(&:publication_queued?).min_by(&:id)
  end

  def current_delivery
    pending = statuses.reject do |status|
      status.publication_published? ||
        status.publication_failed? ||
        status.publication_deleting? ||
        status.publication_delete_failed?
    end
    position = pending.filter_map(&:publication_position).min
    return [] if position.blank?

    pending.select { |status| status.publication_position == position }
  end
end
