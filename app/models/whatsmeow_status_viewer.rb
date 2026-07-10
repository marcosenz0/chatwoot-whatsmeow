class WhatsmeowStatusViewer < ApplicationRecord
  belongs_to :whatsmeow_status, inverse_of: :status_viewers
  belongs_to :contact, optional: true

  validates :viewer_jid, :viewed_at, presence: true
  validates :viewer_jid, uniqueness: { scope: :whatsmeow_status_id }
end
