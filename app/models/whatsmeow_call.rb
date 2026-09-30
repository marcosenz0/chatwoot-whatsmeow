class WhatsmeowCall < ApplicationRecord
  belongs_to :account
  belongs_to :inbox
  belongs_to :contact, optional: true
  belongs_to :conversation, optional: true
  belongs_to :agent, class_name: 'User', optional: true

  validates :source_id, presence: true, uniqueness: { scope: :inbox_id }
  validates :peer_jid, :direction, :status, :started_at, presence: true
  validates :direction, inclusion: { in: %w[incoming outgoing] }
  validates :status, inclusion: { in: %w[ringing connected completed missed unanswered declined failed] }

  def duration_seconds
    return 0 unless connected_at && ended_at

    [(ended_at - connected_at).to_i, 0].max
  end
end
