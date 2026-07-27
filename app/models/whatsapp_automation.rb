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
  before_validation :return_changed_active_automation_to_draft, on: :update
  after_update_commit :cancel_runs_for_replaced_definition

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
    transaction do
      update!(status: :paused)
      cancel_unfinished_runs
    end
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

  def return_changed_active_automation_to_draft
    return unless status_in_database == 'active'
    return unless will_save_change_to_definition? || will_save_change_to_trigger_type? || will_save_change_to_trigger_config?

    @cancel_runs_for_replaced_definition = true
    self.status = :draft
    self.published_at = nil
  end

  def cancel_runs_for_replaced_definition
    return unless @cancel_runs_for_replaced_definition

    cancel_unfinished_runs
    @cancel_runs_for_replaced_definition = false
  end

  def cancel_unfinished_runs
    runs.unfinished.find_each { |run| run.update!(status: :cancelled, next_run_at: nil) }
  end

  def validate_publishable_definition!
    validation_errors = Whatsapp::Automation::DefinitionValidator.new(definition, publish: true).validate
    validation_errors.concat(publishable_configuration_errors)
    validation_errors.uniq!
    return if validation_errors.empty?

    validation_errors.each { |error| errors.add(:definition, error) }
    raise ActiveRecord::RecordInvalid, self
  end

  def publishable_configuration_errors
    validation_errors = []
    keywords = Array(trigger_config['keywords']).map { |keyword| keyword.to_s.strip }.compact_blank
    validation_errors << 'keyword automations need at least one keyword' if trigger_type == 'keyword' && keywords.empty?
    validation_errors.concat(template_node_errors)
    validation_errors
  end

  def template_node_errors
    templates = Array(inbox.channel.message_templates)
    Array(definition['nodes']).flat_map { |node| template_node_errors_for(node, templates) }
  end

  def template_node_errors_for(node, templates)
    config = node.fetch('config', {}).with_indifferent_access
    return [] unless node['type'] == 'message' && config[:mode] == 'template'

    template = matching_template(templates, config)
    return ["template node #{node['id']} does not match a synchronized template"] if template.blank?
    return ["template node #{node['id']} must use an approved template"] unless template['status'].to_s.casecmp?('approved')

    Whatsapp::Automation::TemplateDefinitionValidator.new(
      node_id: node['id'],
      config: config,
      template: template
    ).validate
  end

  def matching_template(templates, config)
    templates.find do |record|
      record['name'] == config[:template_name] &&
        record['language'].to_s.casecmp?(config[:language].to_s)
    end
  end
end
