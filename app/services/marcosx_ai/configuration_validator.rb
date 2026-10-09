class MarcosxAi::ConfigurationValidator
  def self.validate!(config, account:)
    raise ArgumentError, 'Invalid memory mode' unless %w[legacy summary_recent selected_only].include?(config[:memory_mode])
    raise ArgumentError, 'Invalid resume mode' unless %w[manual after_human].include?(config[:resume_mode])

    interval = config[:resume_after_minutes]
    raise ArgumentError, 'Invalid resume interval' unless interval.is_a?(Integer) && interval.between?(1, 10_080)

    rules = config[:alert_rules]
    raise ArgumentError, 'Invalid rules' unless rules.is_a?(Array) && rules.size <= 50

    ids = rules.map { |rule| rule[:id] }
    raise ArgumentError, 'Duplicate rule IDs' unless ids.uniq.size == ids.size

    validate_destinations!(config[:notifications], account)
    rules.each do |rule|
      unless rule[:id].is_a?(String) && rule[:id].match?(/\A[a-zA-Z0-9_-]{1,80}\z/) && rule[:id] != 'human_handoff' &&
             rule[:name].is_a?(String) && rule[:name].present? && rule[:description].is_a?(String) && rule[:description].present? &&
             %w[notify pause].include?(rule[:action]) && rule[:message].is_a?(String)
        raise ArgumentError, 'Invalid alert rule'
      end

      validate_destinations!(config[:notifications].merge(rule), account)
    end
  end

  def self.validate_destinations!(settings, account)
    raise ArgumentError, 'Invalid destinations' unless settings.is_a?(Hash)

    users = settings[:user_ids]
    numbers = settings[:whatsapp_numbers]
    unless users.is_a?(Array) && users.all? { |id| id.is_a?(Integer) && id.positive? } &&
           users.uniq.size == users.size && account.users.where(id: users).count == users.size && numbers.is_a?(Array) &&
           numbers.size <= 20 && numbers.all? { |number| number.is_a?(String) && number.match?(/\A\+[1-9]\d{7,14}\z/) } &&
           numbers.uniq.size == numbers.size
      raise ArgumentError, 'Invalid recipients'
    end

    inbox_id = settings[:inbox_id]
    return if numbers.empty? && inbox_id.nil?
    return if inbox_id.is_a?(Integer) && account.inboxes.where(id: inbox_id, channel_type: 'Channel::Whatsmeow').exists?

    raise ArgumentError, 'Select a WhatsApp Direct inbox'
  end
end
