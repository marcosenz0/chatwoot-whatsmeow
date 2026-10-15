class MarcosxAi::NotificationTarget < ApplicationRecord
  include MarcosxAiAudience

  self.table_name = 'marcosx_ai_notification_targets'
  belongs_to :account
  belongs_to :assistant, class_name: 'MarcosxAi::Assistant', inverse_of: :notification_targets
  belongs_to :inbox, class_name: '::Inbox'

  validates :title, length: { maximum: 120 }
  validates :number, format: { with: /\A\+[1-9]\d{7,14}\z/ }, uniqueness: { scope: :assistant_id }
  validates :enabled, inclusion: { in: [true, false] }
  validate :valid_destination

  scope :available, -> { where(enabled: true) }
  scope :ordered, -> { order(:id) }

  def public_data
    { id: id, title: title, number: number, inbox_id: inbox_id, enabled: enabled }.merge(audience_data)
  end

  private

  def valid_destination
    return if assistant&.account_id == account_id && inbox&.account_id == account_id && inbox.channel_type == 'Channel::Whatsmeow'

    errors.add(:inbox, :invalid)
  end
end
