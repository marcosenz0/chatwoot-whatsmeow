class MarcosxAi::Resource < ApplicationRecord
  include Rails.application.routes.url_helpers
  self.table_name = 'marcosx_ai_resources'
  MAX_ITEMS = 100
  MAX_BYTES = 40.megabytes
  CONTENT_TYPES = %w[image/jpeg image/png image/webp image/gif video/mp4 video/webm video/quicktime application/pdf text/plain].freeze
  belongs_to :account
  belongs_to :assistant, class_name: 'MarcosxAi::Assistant', inverse_of: :resources
  has_one_attached :file
  before_validation :set_file_kind
  validates :title, presence: true, length: { maximum: 120 }
  validates :description, presence: true, length: { maximum: 800 }
  validates :kind, inclusion: { in: %w[image video file link] }
  validates :url, length: { maximum: 2048 }
  validate :valid_source

  scope :available, -> { where(enabled: true) }
  scope :ordered, -> { order(Arel.sql('LOWER(title) ASC'), :id) }

  def catalog_data
    { id: id, title: title, description: description, kind: kind }
  end

  def public_data
    catalog_data.merge(
      enabled: enabled, url: url, file_name: file.attached? ? file.filename.to_s : nil,
      file_size: file.attached? ? file.byte_size : nil, file_url: file.attached? ? url_for(file) : nil,
      thumb_url: kind.in?(%w[image video]) && file.attached? ? url_for(file.representation(resize_to_limit: [320, 240])) : nil
    )
  end

  private

  def set_file_kind
    return if kind == 'link' || !file.attached?

    media = file.content_type.to_s.split('/').first
    self.kind = media.in?(%w[image video]) ? media : 'file'
    self.url = nil
  end

  def valid_source
    errors.add(:assistant, 'must belong to the account') if assistant && assistant.account_id != account_id
    if kind == 'link'
      uri = URI.parse(url.to_s)
      errors.add(:url, 'must be an HTTP or HTTPS link') unless uri.is_a?(URI::HTTP) && uri.host.present? && uri.userinfo.nil?
      errors.add(:file, 'must be empty for links') if file.attached?
    elsif file.attached?
      errors.add(:file, 'type not supported') unless CONTENT_TYPES.include?(file.content_type)
      errors.add(:file, 'size exceeds 40 MB') if file.byte_size > MAX_BYTES
    else
      errors.add(:file, 'is required')
    end
  rescue URI::InvalidURIError
    errors.add(:url, 'must be an HTTP or HTTPS link')
  end
end
