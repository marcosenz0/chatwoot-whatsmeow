class MarcosxAi::PromptRules
  FIELDS = %w[platform current_request memory].freeze
  LIMITS = { 'platform' => 30_000, 'current_request' => 8000, 'memory' => 8000 }.freeze
  DATA_FIELDS = %w[resource_catalog pix_catalog alert_rules].freeze
  SETTING_FIELDS = %w[max_message_parts message_target_characters min_text_turns long_message_characters
                      max_voice_characters voice_instructions].freeze
  PLACEHOLDERS = (DATA_FIELDS + SETTING_FIELDS).freeze
  TOKEN = /\{\{\s*([a-z_]+)\s*\}\}/.freeze

  def self.value(assistant, field, default)
    assistant&.resolved_config&.dig(:prompt_rules, field).nil? ? default : assistant.resolved_config.dig(:prompt_rules, field)
  end

  def self.custom?(assistant)
    !assistant.resolved_config.dig(:prompt_rules, :platform).nil?
  end

  def self.defaults(assistant)
    {
      platform: MarcosxAi::PromptBuilder.platform_instructions(assistant, assistant.feature_enabled?(:allow_reactions), false,
                                                              use_override: false, template: true),
      current_request: MarcosxAi::PromptBuilder::CURRENT_REQUEST_INSTRUCTIONS,
      memory: MarcosxAi::ConversationContext::MEMORY_PROMPT
    }
  end

  def self.render(text, assistant:, conversation: nil, stable: false)
    settings = assistant.resolved_config
    values = {
      'max_message_parts' => assistant.max_message_parts,
      'message_target_characters' => settings[:message_target_characters],
      'min_text_turns' => settings.dig(:voice, :min_text_turns),
      'long_message_characters' => settings.dig(:voice, :long_message_characters),
      'max_voice_characters' => settings.dig(:voice, :max_characters),
      'voice_instructions' => settings.dig(:voice, :instructions)
    }
    values.merge!(stable ? DATA_FIELDS.index_with { '' } : data(assistant, conversation))
    # Single-pass substitution: values from catalogs never become template code.
    text.gsub(TOKEN) { values.fetch(Regexp.last_match(1)).to_s }
  end

  def self.data(assistant, conversation)
    {
      'resource_catalog' => MarcosxAi::ResourceCatalog.context_data(assistant, conversation: conversation),
      'pix_catalog' => MarcosxAi::PixCatalog.context_data(assistant, conversation: conversation),
      'alert_rules' => assistant.alert_rules.map { |rule| rule.slice(:id, :name, :description, :action) }.to_json
    }
  end

  def self.runtime_data(assistant, conversation)
    template = assistant.resolved_config.dig(:prompt_rules, :platform)
    fields = template.scan(TOKEN).flatten & DATA_FIELDS
    data(assistant, conversation).slice(*fields).to_json
  end

  def self.validate!(config)
    rules = config[:prompt_rules]
    validate_rules!(rules)
    presets = config[:prompt_presets]
    unless presets.is_a?(Array) && presets.size <= 20 && presets.map { |preset| preset.is_a?(Hash) ? preset[:id] : nil }.uniq.size == presets.size
      raise ArgumentError, I18n.t('marcosx_ai.errors.invalid_prompt_presets')
    end
    presets.each do |preset|
      unless preset.is_a?(Hash) && preset[:id].is_a?(String) && preset[:id].match?(/\A[a-zA-Z0-9_-]{1,80}\z/) &&
             !%w[system custom].include?(preset[:id]) && preset[:name].is_a?(String) && preset[:name].strip.length.between?(1, 80)
        raise ArgumentError, I18n.t('marcosx_ai.errors.invalid_prompt_presets')
      end
      validate_rules!(preset[:rules], complete: true)
    end
    id = config[:prompt_preset_id]
    unless id.is_a?(String) && (%w[system custom] + presets.map { |preset| preset[:id] }).include?(id)
      raise ArgumentError, I18n.t('marcosx_ai.errors.invalid_prompt_presets')
    end
  end

  def self.validate_rules!(rules, complete: false)
    unless rules.is_a?(Hash) && (rules.keys.map(&:to_s) - FIELDS).empty? &&
           (!complete || FIELDS.all? { |field| rules.key?(field) || rules.key?(field.to_sym) })
      raise ArgumentError, I18n.t('marcosx_ai.errors.invalid_prompt_rules')
    end
    rules.each do |field, text|
      next if text.nil? && !complete

      allowed = field.to_s == 'platform' ? PLACEHOLDERS : []
      unless text.is_a?(String) && text.length <= LIMITS.fetch(field.to_s) && (text.scan(TOKEN).flatten - allowed).empty?
        raise ArgumentError, I18n.t('marcosx_ai.errors.invalid_prompt_rules')
      end
    end
  end
end
