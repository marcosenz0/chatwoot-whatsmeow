class MarcosxAi::PixKey < ApplicationRecord
  self.table_name = 'marcosx_ai_pix_keys'
  belongs_to :account
  belongs_to :assistant, class_name: 'MarcosxAi::Assistant', inverse_of: :pix_keys

  before_validation :normalize_payload
  validates :title, presence: true, length: { maximum: 120 }
  validates :description, length: { maximum: 800 }
  validates :key, uniqueness: { scope: :assistant_id }
  validates :position, inclusion: { in: [1, 2] }, allow_nil: true
  validate :valid_payload
  scope :available, -> { where.not(position: nil).order(:position) }
  scope :ordered, -> { order(Arel.sql('position ASC NULLS LAST'), Arel.sql('LOWER(title) ASC'), :id) }

  def payload
    Whatsmeow::PixPayload.new(key_type: key_type, key: key, merchant_name: merchant_name)
  end

  def public_data
    payload.to_h.merge(id: id, title: title, description: description, enabled: position.present?, primary: position == 1)
  end

  # Two database slots enforce the limit even when two administrators activate keys together.
  def configure!(attributes)
    assistant.with_lock do
      reload if persisted?
      enabled = attributes.delete('enabled')
      primary = attributes.delete('primary')
      assign_attributes(attributes)
      self.position = nil if enabled == false
      if enabled == true && position.nil?
        self.position = ([1, 2] - assistant.pix_keys.available.pluck(:position)).first
        raise ArgumentError, I18n.t('marcosx_ai.errors.pix_active_limit') if position.nil?
      end
      save!
      if primary && position.present? && position != 1
        previous = assistant.pix_keys.find_by(position: 1)
        update!(position: nil)
        previous&.update!(position: 2)
        update!(position: 1)
      end
      assistant.pix_keys.find_by(position: 2)&.update!(position: 1) unless assistant.pix_keys.exists?(position: 1)
      reload
    end
  end

  private

  def normalize_payload
    assign_attributes(payload.to_h)
  end

  def valid_payload
    errors.add(:assistant, :invalid) if assistant && assistant.account_id != account_id
    errors.add(:key, :invalid) unless payload.valid?
  end
end
