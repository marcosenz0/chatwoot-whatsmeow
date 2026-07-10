class Whatsmeow::StatusViewService
  pattr_initialize [:status!, :user!]

  def perform
    view = status.views.create_or_find_by!(user: user) { |record| record.viewed_at = Time.current }
    Whatsmeow::SendStatusReadReceiptJob.perform_later(status.id) unless status.from_me? || status.read_receipt_sent_at.present?
    view
  end
end
