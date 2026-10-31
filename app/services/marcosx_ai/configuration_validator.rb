class MarcosxAi::ConfigurationValidator
  def self.validate!(config, account:)
    raise ArgumentError, 'Invalid manual sessions setting' unless [true, false].include?(config[:manual_sessions_enabled])

    unless config[:message_target_characters].is_a?(Integer) && config[:message_target_characters].between?(40, 1500) &&
           [true, false].include?(config[:separate_greeting])
      raise ArgumentError, 'Invalid message splitting settings'
    end
    raise ArgumentError, 'Invalid emoji usage' unless %w[none occasional expressive].include?(config[:emoji_usage])

    cache = config[:prompt_cache]
    unless cache.is_a?(Hash) && [true, false].include?(cache[:enabled]) && MarcosxAi::PromptCache::LIFETIMES.include?(cache[:ttl])
      raise ArgumentError, 'Invalid prompt cache settings'
    end

    MarcosxAi::PromptRules.validate!(config)
    validate_voice!(config[:voice])
    validate_transcription!(config[:transcription])
    validate_vision!(config[:vision])
    validate_connections!(config, account)
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

  def self.validate_transcription!(settings)
    unless settings.is_a?(Hash) && settings[:model].is_a?(String) &&
           ((settings[:provider] == 'agent' && settings[:model].empty?) ||
             MarcosxAi::TranscriptionClient::MODELS[settings[:provider]]&.include?(settings[:model]))
      raise ArgumentError, 'Invalid transcription provider or model'
    end
  end

  def self.validate_vision!(settings)
    unless settings.is_a?(Hash) && settings[:model].is_a?(String) &&
           ((settings[:provider] == 'agent' && settings[:model].empty?) ||
             (MarcosxAi::Credential::PROVIDERS.key?(settings[:provider]) && settings[:model].present? &&
               MarcosxAi::ModelCatalog.describe(settings[:model], settings[:provider])[:vision])) &&
           settings[:max_dimension].is_a?(Integer) && settings[:max_dimension].between?(512, 1600) &&
           settings[:video_frames].is_a?(Integer) && settings[:video_frames].between?(1, 6) &&
           settings[:video_interval_seconds].is_a?(Integer) && settings[:video_interval_seconds].between?(1, 30) &&
           settings[:instructions].is_a?(String) && settings[:instructions].length <= 4000
      raise ArgumentError, 'Invalid image reading settings'
    end
  end

  def self.validate_connections!(config, account)
    %w[chat vision transcription].each do |feature|
      settings = feature == 'chat' ? config : config[feature]
      [settings, settings[:fallback]].each do |target|
        limit = target[:max_output_tokens] if target.is_a?(Hash)
        next if limit.nil? || (limit.is_a?(Integer) && limit.between?(128, 32_768))

        raise ArgumentError, I18n.t('marcosx_ai.errors.invalid_output_limit')
      end
      provider = settings[:provider] == 'agent' ? config[:provider] : settings[:provider]
      validate_connection_id!(settings[:connection_id], provider, account)
      backup = settings[:fallback]
      unless backup.is_a?(Hash) && [true, false].include?(backup[:enabled]) && [true, false].include?(backup[:retry_primary]) &&
             MarcosxAi::Credential::PROVIDERS.key?(backup[:provider]) && backup[:model].is_a?(String) && backup[:model].present?
        raise ArgumentError, I18n.t('marcosx_ai.errors.invalid_fallback')
      end

      validate_connection_id!(backup[:connection_id], backup[:provider], account)
      next unless backup[:enabled]

      if feature == 'vision' && !MarcosxAi::ModelCatalog.describe(backup[:model], backup[:provider])[:vision]
        raise ArgumentError, I18n.t('marcosx_ai.errors.invalid_fallback')
      end
      if feature == 'transcription' && !MarcosxAi::TranscriptionClient::MODELS.fetch(backup[:provider]).include?(backup[:model])
        raise ArgumentError, I18n.t('marcosx_ai.errors.invalid_fallback')
      end

      main_id = settings[:connection_id] || (settings[:provider] == 'agent' ? config[:connection_id] : nil)
      main = MarcosxAi::Credential.for_provider(account, provider, id: main_id)
      reserve = MarcosxAi::Credential.for_provider(account, backup[:provider], id: backup[:connection_id])
      if provider == backup[:provider] && main&.id == reserve&.id
        raise ArgumentError, I18n.t('marcosx_ai.errors.same_fallback')
      end
    end
  end

  def self.validate_connection_id!(id, provider, account)
    return if id.nil?
    return if id.is_a?(Integer) && account.marcosx_ai_credentials.where(id: id, provider: provider).exists?

    raise ArgumentError, I18n.t('marcosx_ai.errors.invalid_connection')
  end

  def self.validate_voice!(settings)
    unless settings.is_a?(Hash) && [true, false].include?(settings[:enabled]) &&
           MarcosxAi::VoiceCredential::PROVIDERS.include?(settings[:provider]) && %w[requested contextual].include?(settings[:mode]) &&
           [true, false].include?(settings[:send_text]) && settings[:max_characters].is_a?(Integer) &&
           settings[:min_text_turns].is_a?(Integer) && settings[:min_text_turns].between?(1, 30) &&
           settings[:long_message_characters].is_a?(Integer) && settings[:long_message_characters].between?(100, 2000) &&
           settings[:max_characters].between?(100, 3000) && settings[:instructions].is_a?(String) &&
           settings[:instructions].length <= 4000 && settings[:pronunciation].is_a?(String) && settings[:pronunciation].length <= 4000
      raise ArgumentError, 'Invalid voice settings'
    end

    MarcosxAi::VoiceCredential::PROVIDERS.each do |provider|
      options = settings[provider]
      unless options.is_a?(Hash) && options[:voice_id].is_a?(String) &&
             (options[:voice_id].empty? || options[:voice_id].match?(/\A[a-zA-Z0-9_-]{1,120}\z/)) &&
             MarcosxAi::VoiceClient::MODELS.fetch(provider).include?(options[:model])
        raise ArgumentError, 'Invalid voice provider settings'
      end

      range = provider == 'minimax' ? (0.5..2.0) : (0.7..1.2)
      unless options[:speed].is_a?(Numeric) && range.cover?(options[:speed])
        raise ArgumentError, 'Invalid voice speed'
      end

      fields = provider == 'minimax' ? { volume: 0.1..10.0, pitch: -12..12 } :
        { stability: 0.0..1.0, similarity_boost: 0.0..1.0, style: 0.0..1.0 }
      fields.each do |field, allowed|
        raise ArgumentError, 'Invalid voice parameter' unless options[field].is_a?(Numeric) && allowed.cover?(options[field])
      end
      raise ArgumentError, 'Invalid voice pitch' if provider == 'minimax' && !options[:pitch].is_a?(Integer)
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
