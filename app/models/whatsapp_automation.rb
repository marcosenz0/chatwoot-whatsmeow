class WhatsappAutomation < ApplicationRecord
  belongs_to :account
  belongs_to :inbox

  has_many :runs, class_name: 'WhatsappAutomationRun', dependent: :destroy_async

  enum status: { draft: 0, active: 1, paused: 2 }

  validates :name, :trigger_type, presence: true
  validates :trigger_type, inclusion: { in: %w[keyword any_message] }
  validate :inbox_belongs_to_account
  validate :official_whatsapp_cloud_inbox
  validate :valid_definition

  scope :enabled, -> { active.where.not(published_at: nil) }

  def enabled?
    active? && published_at.present?
  end

  def publish!
    transaction do
      validate_publishable_definition!
      update!(status: :active, published_at: Time.current)
    end
  end

  def pause!
    update!(status: :paused)
  end

  def trigger_matches?(message)
    return false unless message.incoming?
    return true if trigger_type == 'any_message'

    keywords = Array(trigger_config['keywords']).map { |keyword| keyword.to_s.downcase.strip }.compact_blank
    keywords.any? { |keyword| message.content.to_s.downcase.include?(keyword) }
  end

  private

  def inbox_belongs_to_account
    return if inbox.blank? || inbox.account_id == account_id

    errors.add(:inbox_id, 'must belong to the same account')
  end

  def official_whatsapp_cloud_inbox
    return if inbox.blank?
    return if inbox.channel_type == 'Channel::Whatsapp' && inbox.channel.provider == 'whatsapp_cloud'

    errors.add(:inbox_id, 'must be an official WhatsApp Cloud API inbox')
  end

  def valid_definition
    Whatsapp::Automation::DefinitionValidator.new(definition).validate.each do |error|
      errors.add(:definition, error)
    end
  end

  def validate_publishable_definition!
    validation_errors = Whatsapp::Automation::DefinitionValidator.new(definition, publish: true).validate
    return if validation_errors.empty?

    validation_errors.each { |error| errors.add(:definition, error) }
    raise ActiveRecord::RecordInvalid, self
  end
end
