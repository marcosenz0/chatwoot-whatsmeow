class MarcosxAi::ReplyBatch < ApplicationRecord
  self.table_name = 'marcosx_ai_reply_batches'
  belongs_to :account
  belongs_to :assistant, class_name: 'MarcosxAi::Assistant'
  belongs_to :user
  has_many :items, class_name: 'MarcosxAi::ReplyBatchItem', dependent: :destroy
  validates :mode, inclusion: { in: %w[review direct] }
  validates :status, inclusion: { in: %w[preparing ready running completed cancelled] }
  validates :request_id, presence: true, length: { maximum: 80 }

  def public_data
    { id: id, assistant_id: assistant_id, assistant_name: assistant.name, mode: mode, status: status, counts: items.group(:status).count,
      items: items.includes(conversation: [:contact, :inbox]).order(:id).map(&:public_data) }
  end

  def continue_later(wait: 0)
    MarcosxAi::ReplyBatchJob.set(wait: wait.seconds).perform_later(id)
  end

  def cancel!
    with_lock { update!(status: 'cancelled') unless status == 'completed' }
    items.where.not(status: %w[sent skipped failed discarded]).find_each(&:discard!)
  end
end
