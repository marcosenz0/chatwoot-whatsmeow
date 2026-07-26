class WhatsappAutomationRun < ApplicationRecord
  belongs_to :account
  belongs_to :whatsapp_automation
  belongs_to :contact
  belongs_to :conversation, optional: true

  enum status: {
    queued: 0,
    running: 1,
    waiting: 2,
    waiting_reply: 3,
    completed: 4,
    failed: 5,
    cancelled: 6
  }

  validates :account_id, :whatsapp_automation_id, :contact_id, presence: true
  validate :associations_belong_to_account

  scope :unfinished, -> { where(status: [:queued, :running, :waiting, :waiting_reply]) }

  delegate :inbox, to: :whatsapp_automation

  private

  def associations_belong_to_account
    return if whatsapp_automation.blank? || contact.blank?

    errors.add(:whatsapp_automation, 'must belong to the same account') if whatsapp_automation.account_id != account_id
    errors.add(:contact, 'must belong to the same account') if contact.account_id != account_id
    errors.add(:conversation, 'must belong to the same account') if conversation.present? && conversation.account_id != account_id
  end
end
