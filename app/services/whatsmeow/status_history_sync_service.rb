class Whatsmeow::StatusHistorySyncService
  pattr_initialize [:inbox!]

  def perform
    return false if anchor.blank?

    Whatsmeow::SessionClient.new(inbox: inbox).sync_status_history(
      message_id: anchor.source_id,
      timestamp: anchor.posted_at.to_i,
      from_me: anchor.from_me?
    )
    true
  end

  private

  def anchor
    @anchor ||= inbox.whatsmeow_statuses.active.where.not(source_id: [nil, '']).order(posted_at: :desc).first
  end
end
