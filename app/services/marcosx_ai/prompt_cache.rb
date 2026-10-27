require 'digest'

class MarcosxAi::PromptCache
  MARKER = :marcosx_cache_prefix
  LIFETIMES = %w[30m 12h].freeze

  def self.supported_model?(model)
    version = model.to_s.match(/\Agpt-(\d+)(?:\.(\d+))?(?:-|$)/)
    version && (version[1].to_i >= 6 || (version[1].to_i == 5 && version[2].to_i >= 6))
  end

  def self.enabled?(assistant)
    assistant.provider == 'openai' && supported_model?(assistant.model) && assistant.resolved_config.dig(:prompt_cache, :enabled) == true
  end

  def self.mark!(message, assistant)
    message[MARKER] = { account_id: assistant.account_id, assistant_id: assistant.id,
                        ttl: assistant.resolved_config.dig(:prompt_cache, :ttl) }
    message
  end

  def self.parameters(messages, account_id:, model:)
    input = messages.map { |message| message.except(MARKER) }
    return { input: input } unless supported_model?(model)

    # Unmarked auxiliary requests and disabled agents must not write their changing suffixes.
    result = { input: input, prompt_cache_options: { mode: 'explicit', ttl: '30m' } }
    index = messages.index { |message| message[MARKER].present? }
    return result unless index

    marker = messages[index][MARKER]
    message = input[index]
    return result unless marker[:account_id] == account_id && marker[:assistant_id].present? &&
                         LIFETIMES.include?(marker[:ttl]) && message[:role].in?(%w[system developer]) && message[:content].is_a?(String)

    message[:content] = [{ type: 'input_text', text: message[:content], prompt_cache_breakpoint: { mode: 'explicit' } }]
    scope = "#{account_id}:#{marker[:assistant_id]}"
    result.merge(prompt_cache_key: "marcoxia-v1-#{Digest::SHA256.hexdigest(scope)[0, 32]}",
                 prompt_cache_options: { mode: 'explicit', ttl: marker[:ttl] })
  end
end
