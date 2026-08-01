class WhatsmeowStatusViewer < ApplicationRecord
  belongs_to :whatsmeow_status, inverse_of: :status_viewers
  belongs_to :contact, optional: true

  validates :viewer_jid, :viewed_at, presence: true
  validates :viewer_jid, uniqueness: { scope: :whatsmeow_status_id }

  def identity_key
    return "contact:#{contact_id}" if contact_id.present?

    digits = viewer_phone.to_s.delete('^0-9')
    return "phone:#{digits}" if digits.present?

    "jid:#{viewer_jid.to_s.downcase}"
  end
end
