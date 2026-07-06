class ConversationPipeline < ApplicationRecord
  DEFAULT_COLOR = '#1f93ff'.freeze

  belongs_to :account
  has_many :stages,
           -> { order(position: :asc, id: :asc) },
           class_name: 'ConversationPipelineStage',
           inverse_of: :conversation_pipeline,
           dependent: :destroy_async
  has_many :active_stages,
           -> { active.order(position: :asc, id: :asc) },
           class_name: 'ConversationPipelineStage',
           inverse_of: :conversation_pipeline,
           dependent: nil
  has_many :conversations, dependent: :nullify

  validates :name, presence: true
  validates :internal_name, presence: true, uniqueness: { scope: :account_id }
  validates :color, presence: true
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  before_validation :normalize_internal_name
  before_validation :set_position, on: :create
  before_validation :set_color
  before_save :unset_other_default_pipelines, if: :default?

  scope :active, -> { where(archived: false) }
  scope :ordered, -> { order(position: :asc, id: :asc) }

  def push_event_data
    {
      id: id,
      name: name,
      internal_name: internal_name,
      description: description,
      color: color,
      position: position,
      default: default,
      archived: archived,
      stages: active_stages.map(&:push_event_data)
    }
  end

  private

  def normalize_internal_name
    self.internal_name = (internal_name.presence || name).to_s.parameterize(separator: '_')
    self.internal_name = "pipeline_#{SecureRandom.hex(3)}" if internal_name.blank?
  end

  def set_position
    self.position = (account&.conversation_pipelines&.maximum(:position) || -1) + 1 if position.nil?
  end

  def set_color
    self.color = color.presence || DEFAULT_COLOR
  end

  def unset_other_default_pipelines
    account.conversation_pipelines.where(default: true).where.not(id: id).find_each do |pipeline|
      pipeline.update!(default: false)
    end
  end
end
