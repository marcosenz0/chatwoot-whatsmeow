class MarcosxAi::Inbox < ApplicationRecord
  self.table_name = 'marcosx_ai_inboxes'

  belongs_to :account
  belongs_to :assistant, class_name: 'MarcosxAi::Assistant'
  belongs_to :inbox

  validates :inbox_id, uniqueness: true
  validate :same_account

  private

  def same_account
    return if account_id.blank? || inbox.blank? || assistant.blank?

    errors.add(:inbox, 'must belong to the same account') if inbox.account_id != account_id
    errors.add(:assistant, 'must belong to the same account') if assistant.account_id != account_id
  end
end
