class WhatsmeowMessageStar < ApplicationRecord
  belongs_to :inbox
  belongs_to :message, optional: true

  validates :chat_jid, :source_id, :occurred_at, presence: true
  validates :source_id, uniqueness: { scope: [:inbox_id, :chat_jid] }, on: :update
  validates :starred, inclusion: { in: [true, false] }
end
