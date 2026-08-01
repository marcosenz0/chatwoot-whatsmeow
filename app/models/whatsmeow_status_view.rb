class WhatsmeowStatusView < ApplicationRecord
  belongs_to :whatsmeow_status, inverse_of: :views
  belongs_to :user

  validates :user_id, uniqueness: { scope: :whatsmeow_status_id }
end
