class Whatsmeow::StatusViewService
  pattr_initialize [:status!, :user!]

  def perform
    view = status.views.create_or_find_by!(user: user) { |record| record.viewed_at = Time.current }
    unless status.from_me? || status.read_receipt_sent_at.present? || status.inbox.channel.hide_status_views?
      Whatsmeow::SendStatusReadReceiptJob.perform_later(status.id)
    end
    view
  end
end
