class MarcosxAi::NotificationRecipients
  def self.legacy(assistant)
    settings = [assistant.resolved_config[:notifications], *assistant.alert_rules]
    settings.flat_map do |entry|
      entry.fetch(:whatsapp_numbers, []).map do |number|
        inbox_id = entry[:inbox_id] || assistant.resolved_config.dig(:notifications, :inbox_id)
        { id: "legacy_#{Digest::SHA256.hexdigest(number)[0, 16]}", title: '', number: number, inbox_id: inbox_id,
          enabled: true, audience: 'global', contact_ids: [], audience_contacts: [], conversation_id: nil }
      end
    end.uniq { |entry| entry[:number] }
  end

  def self.list(assistant)
    managed = assistant.notification_targets.ordered.to_a
    managed.map(&:public_data) + legacy(assistant).reject { |item| managed.any? { |target| target.number == item[:number] } }
  end

  def self.configuration(assistant:, conversation:, rule: {})
    settings = assistant.resolved_config[:notifications].merge(rule).stringify_keys
    managed_numbers = assistant.notification_targets.pluck(:number)
    numbers = settings.fetch('whatsapp_numbers', []) - managed_numbers
    targets = assistant.notification_targets.available.available_to(conversation).ordered
    settings.merge('whatsapp_numbers' => (numbers + targets.map(&:number)).uniq,
                   'whatsapp_routes' => targets.to_h { |target| [target.number, target.inbox_id] },
                   'notification_target_ids' => targets.to_h { |target| [target.number, target.id] })
  end

  def self.remove_legacy!(assistant, number)
    config = assistant.config.deep_dup.with_indifferent_access
    [config[:notifications], *Array(config[:alert_rules])].compact.each do |entry|
      entry[:whatsapp_numbers] = entry[:whatsapp_numbers] - [number] if entry[:whatsapp_numbers].is_a?(Array)
    end
    assistant.update!(config: config) if config != assistant.config.with_indifferent_access
  end

  def self.allowed_delivery?(alert, number)
    expected_id = alert.configuration.dig('notification_target_ids', number)
    target = alert.assistant.notification_targets.find_by(number: number)
    unless target
      rule = alert.assistant.alert_rules.find { |entry| entry[:id] == alert.rule_id } || {}
      return expected_id.nil? && configuration(assistant: alert.assistant, conversation: alert.conversation,
                                               rule: rule)['whatsapp_numbers'].include?(number)
    end
    return false if expected_id && target.id != expected_id

    alert.assistant.notification_targets.available.available_to(alert.conversation).exists?(id: target.id)
  end
end
