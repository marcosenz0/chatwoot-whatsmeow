class WhatsmeowSticker < ApplicationRecord
  belongs_to :account
  belongs_to :user
  belongs_to :attachment

  validates :attachment_id, uniqueness: { scope: [:account_id, :user_id] }
  validate :attachment_must_be_sticker

  private

  def attachment_must_be_sticker
    return if attachment&.meta&.with_indifferent_access&.fetch(:whatsmeow_sticker, false)

    errors.add(:attachment, 'must be a WhatsApp sticker')
  end
end
