class WhatsmeowStatus < ApplicationRecord
  belongs_to :account
  belongs_to :inbox
  belongs_to :contact, optional: true
  belongs_to :created_by, class_name: 'User', optional: true, inverse_of: :created_whatsmeow_statuses

  has_many :views, class_name: 'WhatsmeowStatusView', dependent: :destroy, inverse_of: :whatsmeow_status
  has_many :status_viewers, class_name: 'WhatsmeowStatusViewer', dependent: :destroy, inverse_of: :whatsmeow_status
  has_one_attached :media

  enum :status_type, { text: 0, image: 1, video: 2, audio: 3 }
  enum :publication_state, { queued: 0, processing: 1, published: 2, failed: 3 }, prefix: :publication

  validates :source_id, presence: true, uniqueness: { scope: :inbox_id }
  validates :sender_jid, :posted_at, :expires_at, presence: true
  validate :content_or_media_present
  validate :acceptable_media

  scope :active, -> { where('expires_at > ?', Time.current) }

  private

  def content_or_media_present
    return if content.present? || media.attached?

    errors.add(:base, 'Status content or media is required')
  end

  def acceptable_media
    return unless media.attached?

    supported_type = media.blob.content_type.to_s.start_with?('image/', 'video/', 'audio/')
    errors.add(:media, 'type is not supported') unless supported_type
    errors.add(:media, 'is too large') if media.blob.byte_size > maximum_media_size
  end

  def maximum_media_size
    limit_mb = GlobalConfigService.load('MAXIMUM_FILE_UPLOAD_SIZE', 40).to_i
    limit_mb = 40 if limit_mb <= 0
    limit_mb.megabytes
  end
end
