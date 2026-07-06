class ConversationPipelineStage < ApplicationRecord
  DEFAULT_COLOR = '#1f93ff'.freeze

  belongs_to :account
  belongs_to :conversation_pipeline
  has_many :conversations, dependent: :nullify

  enum category: { open: 0, won: 1, lost: 2 }

  validates :name, presence: true
  validates :internal_name, presence: true, uniqueness: { scope: :conversation_pipeline_id }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :probability, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 },
                          allow_nil: true
  validates :stale_after_days, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validate :stage_account_matches_pipeline

  before_validation :normalize_internal_name
  before_validation :set_account_from_pipeline
  before_validation :set_position, on: :create
  before_validation :set_color

  scope :active, -> { where(archived: false) }
  scope :ordered, -> { order(position: :asc, id: :asc) }

  def push_event_data
    {
      id: id,
      name: name,
      internal_name: internal_name,
      position: position,
      color: color,
      category: category,
      probability: probability,
      stale_after_days: stale_after_days,
      archived: archived
    }
  end

  private

  def normalize_internal_name
    self.internal_name = (internal_name.presence || name).to_s.parameterize(separator: '_')
    self.internal_name = "stage_#{SecureRandom.hex(3)}" if internal_name.blank?
  end

  def set_account_from_pipeline
    self.account_id ||= conversation_pipeline&.account_id
  end

  def set_position
    return if position.present? || conversation_pipeline.blank?

    self.position = (conversation_pipeline.stages.maximum(:position) || -1) + 1
  end

  def set_color
    self.color = color.presence || DEFAULT_COLOR
  end

  def stage_account_matches_pipeline
    return if account_id.blank? || conversation_pipeline.blank?

    errors.add(:account_id, 'must match pipeline account') if account_id != conversation_pipeline.account_id
  end
end
