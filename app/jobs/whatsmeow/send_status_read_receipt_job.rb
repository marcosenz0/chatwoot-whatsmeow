class Whatsmeow::SendStatusReadReceiptJob < ApplicationJob
  queue_as :default

  retry_on Whatsmeow::SessionClient::Error, wait: :polynomially_longer, attempts: 5

  def perform(status_id)
    status = WhatsmeowStatus.find_by(id: status_id)
    return if status.blank? || status.from_me? || status.read_receipt_sent_at.present? || status.inbox.channel.hide_status_views?

    status.with_lock do
      next if status.read_receipt_sent_at.present? || status.inbox.channel.hide_status_views?

      Whatsmeow::SessionClient.new(inbox: status.inbox).mark_status_read(
        message_id: status.source_id,
        sender_jid: status.sender_jid,
        timestamp: status.posted_at.to_i
      )
      status.update!(read_receipt_sent_at: Time.current)
    end
  end
end
