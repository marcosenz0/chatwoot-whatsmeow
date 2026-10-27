class MarcosxAi::ProviderUsage
  def self.record(account:, assistant:, conversation:, model:, purpose:, response:, parameters:, started_at:)
    usage = response['usage'] || {}
    details = usage['input_tokens_details'] || {}
    output = usage['output_tokens_details'] || {}
    MarcosxAi::Log.transaction(requires_new: true) do
      MarcosxAi::Log.create!(account: account, assistant: assistant, conversation: conversation, event: 'provider_call', response: {
        provider: 'openai', model: model, purpose: purpose, response_id: response['id'],
        duration_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round,
        input_tokens: usage['input_tokens'], output_tokens: usage['output_tokens'],
        cached_tokens: details['cached_tokens'], cache_write_tokens: details['cache_write_tokens'], reasoning_tokens: output['reasoning_tokens'],
        cache_mode: parameters.dig(:prompt_cache_options, :mode), cache_ttl: parameters.dig(:prompt_cache_options, :ttl),
        prefix_marked: parameters[:prompt_cache_key].present?
      })
    end
  rescue StandardError
    # A metrics failure must not repeat a billed request or discard a valid customer reply.
    Rails.logger.warn('MarcoXIA provider usage could not be recorded')
  end
end
