require 'time'

class MarcosxAi::RateLimitRetry
  MAX_RETRIES = 2
  MAX_WAIT = 60

  def self.delay(error)
    return unless error.response&.dig(:status).to_i == 429

    headers = error.response[:headers] || {}
    raw = headers.find { |key, _| key.to_s.downcase == 'retry-after' }&.last.to_s
    seconds = Float(raw, exception: false)
    if seconds.nil? && raw.present?
      begin
        seconds = Time.httpdate(raw) - Time.current
      rescue ArgumentError
        return nil
      end
    end
    if seconds.nil?
      body = error.response[:body]
      body = JSON.parse(body) if body.is_a?(String)
      message = body.is_a?(Hash) ? body.dig('error', 'message').to_s : ''
      match = message.match(/(?:try|retry)\s+again\s+in\s+(\d+(?:\.\d+)?)\s*(ms|s|seconds?|minutes?|m)\b/i)
      if match
        seconds = match[1].to_f
        seconds *= 60 if %w[m minute minutes].include?(match[2].downcase)
        seconds /= 1000 if match[2].downcase == 'ms'
      end
    end
    seconds if seconds&.finite? && seconds >= 0
  rescue JSON::ParserError
    nil
  end

  def initialize(enabled:)
    @enabled = enabled
    @attempts = 0
    @waited = 0
  end

  def perform
    yield
  rescue Faraday::Error => e
    seconds = self.class.delay(e)
    wait = [seconds.to_f.ceil, 1].max
    raise unless @enabled && seconds && @attempts < MAX_RETRIES && @waited + wait <= MAX_WAIT

    @attempts += 1
    @waited += wait
    Kernel.sleep(wait)
    retry
  end
end
