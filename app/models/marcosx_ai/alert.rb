class MarcosxAi::Alert < ApplicationRecord
  self.table_name = 'marcosx_ai_alerts'

  belongs_to :account
  belongs_to :conversation
  belongs_to :assistant, class_name: 'MarcosxAi::Assistant', optional: true
  belongs_to :resolved_by, class_name: 'User', optional: true
  has_many :deliveries, class_name: 'MarcosxAi::AlertDelivery', dependent: :destroy, inverse_of: :alert
  validates :rule_id, :name, presence: true
  validates :action, inclusion: { in: %w[notify pause] }
  validates :status, inclusion: { in: %w[open resolved] }

  def public_data
    { id: id, rule_id: rule_id, name: name, action: action, status: status, reason: reason, created_at: created_at,
      resolved_at: resolved_at, conversation_id: conversation.display_id, contact: conversation.contact.name,
      deliveries: deliveries.order(:id).map(&:public_data) }
  end
end
