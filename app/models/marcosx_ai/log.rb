class MarcosxAi::Log < ApplicationRecord
  self.table_name = 'marcosx_ai_logs'

  belongs_to :account
  belongs_to :assistant, class_name: 'MarcosxAi::Assistant', optional: true
  belongs_to :conversation, optional: true
end
