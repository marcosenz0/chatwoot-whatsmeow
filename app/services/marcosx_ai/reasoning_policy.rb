class MarcosxAi::ReasoningPolicy
  VALUES = %w[default none minimal low medium high xhigh max].freeze

  # The model-list APIs do not expose effort levels. Keep the documented
  # provider/model capabilities here, shared by the catalog and request builder.
  def self.levels(provider, model)
    id = model.to_s
    case provider
    when 'groq'
      return %w[none default low medium high] if id.match?(/\Aqwen\/qwen3\.8-27b\z/)
      return %w[none default] if id.match?(/\Aqwen\/qwen3\.6-27b\z/)
      return %w[low medium high] if id.match?(/\Aopenai\/gpt-oss-(20b|120b)\z/)
      return %w[low medium high xhigh] if id == 'meta-models/muse-spark-open'
    when 'openai'
      return %w[low medium high xhigh max] if id.match?(/\Agpt-(6-astra|6\.1-sol)(-|$)/)
      return %w[none low medium high xhigh max] if id.match?(/\Agpt-(6(?:\.1)?-(?:sol|terra|luna)|5\.6(?:-(?:sol|terra|luna))?)(-|$)/)
      return %w[none low medium high xhigh] if id.match?(/\Agpt-5\.[245](-|$)/)
      return %w[none low medium high] if id.match?(/\Agpt-5\.1(-|$)/)
      return %w[minimal low medium high] if id.match?(/\Agpt-5(?:-mini|-nano)?(?:-\d|$)/)
      return %w[low medium high] if id.match?(/\Ao[34](-|$)/)
    when 'gemini'
      return %w[default none low medium high] if id.match?(/\Agemini-2\.5-flash(?:-lite)?\z/)
      return %w[default low medium high] if id == 'gemini-2.5-pro'
    end
    []
  end

  def self.resolve(provider, model, value)
    supported = levels(provider, model)
    return nil if supported.empty?
    return value if supported.include?(value)

    return 'default' if provider == 'gemini' || !supported.include?('medium')

    'medium'
  end

  def self.gemini_config(effort)
    return {} if effort.nil? || effort == 'default'

    budget = { 'none' => 0, 'low' => 1024, 'medium' => 4096, 'high' => 8192 }.fetch(effort)
    { thinkingConfig: { thinkingBudget: budget } }
  end
end
