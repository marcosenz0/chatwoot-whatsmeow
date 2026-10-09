class MarcosxAi::AlertDelivery < ApplicationRecord
  self.table_name = 'marcosx_ai_alert_deliveries'
  belongs_to :alert, class_name: 'MarcosxAi::Alert', inverse_of: :deliveries
  belongs_to :message, optional: true
  belongs_to :notification, optional: true
  validates :kind, inclusion: { in: %w[panel whatsapp] }
  validates :recipient, presence: true
  after_create_commit :enqueue_delivery

  def public_data
    delivery_status = message && (message.source_id.present? || message.failed?) ? message.status : status
    { id: id, kind: kind, recipient: recipient, status: delivery_status, attempts: attempts, last_attempt_at: last_attempt_at,
      error: error.presence || message&.content_attributes&.dig('external_error') }
  end

  private

  def enqueue_delivery
    MarcosxAi::AlertDeliveryJob.perform_later(id)
  end
end
