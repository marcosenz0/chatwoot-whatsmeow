require 'digest'

class MarcosxAi::ConnectionRouter
  attr_reader :client

  def initialize(assistant:, feature:, conversation: nil, temperature: 0.7, reasoning_effort: 'medium', purpose: 'other')
    @assistant = assistant
    @version = assistant.updated_at
    @feature = feature
    @conversation = conversation
    @temperature = temperature
    @reasoning_effort = reasoning_effort
    @purpose = purpose
    @endpoints = MarcosxAi::ConnectionPlan.new(assistant: assistant, feature: feature).endpoints
    @signature = Digest::SHA256.hexdigest(@endpoints.map { |e|
      [e[:role], e[:provider], e[:model], e[:max_output_tokens], e[:key], e[:credential]&.updated_at]
    }.to_json)
  end

  def perform(task, **arguments)
    errors = []
    raise CustomExceptions::MarcosxAi, I18n.t('marcosx_ai.errors.unsupported_media') if @endpoints.empty?

    ordered_endpoints.each do |endpoint|
      begin
        @client = MarcosxAi::ProviderClient.new(account: @assistant.account, assistant: @assistant, conversation: @conversation,
                                                provider: endpoint[:provider], model: endpoint[:model], credential: endpoint[:credential],
                                                temperature: @temperature, reasoning_effort: @reasoning_effort, purpose: @purpose,
                                                routing: false, retry_rate_limits: @endpoints.one?, max_output_tokens: endpoint[:max_output_tokens])
        result = @client.public_send(task, **arguments)
        record_outcome(endpoint)
        return result
      rescue CustomExceptions::MarcosxAi => e
        raise unless e.provider_failure

        errors << e
        record_outcome(endpoint, error: e)
      end
    end
    raise errors.first if errors.one?

    raise CustomExceptions::MarcosxAi, I18n.t('marcosx_ai.errors.connections_failed')
  end

  private

  def ordered_endpoints
    status = @assistant.connection_status[@feature] || {}
    primary = @endpoints.first
    health = primary[:credential]&.health.presence || status.dig('connections', primary[:key]) || {}
    retry_at = Time.iso8601(health['retry_at']) if health['retry_at']
    if @endpoints.size > 1 && status['signature'] == @signature && status['active_role'] == 'fallback' &&
       health['state'] == 'error' && retry_at && retry_at > Time.current
      return @endpoints.reverse
    end

    @endpoints
  end

  def record_outcome(endpoint, error: nil)
    ActiveRecord::Base.transaction(requires_new: true) do
      health = endpoint[:credential]&.record_health!(error: error) ||
               (error ? { 'state' => 'error', 'error' => error.message } : { 'state' => 'healthy' })
      record(endpoint, health: health, success: error.nil?)
    end
  rescue ActiveRecord::ActiveRecordError => e
    Rails.logger.warn("[MarcoXIA] connection health persistence failed: #{e.class}")
  end

  def record(endpoint, health:, success:)
    return if @assistant.new_record? || @assistant.has_changes_to_save?

    @assistant.with_lock do
      return unless @assistant.updated_at == @version

      all = @assistant.connection_status.deep_dup
      current = all[@feature] || {}
      current = {} unless current['signature'] == @signature
      current['signature'] = @signature
      current['connections'] ||= {}
      current['connections'][endpoint[:key]] = health.merge('provider' => endpoint[:provider], 'name' => endpoint[:name], 'role' => endpoint[:role])
      current['active_role'] = success ? endpoint[:role] : nil
      current['active_key'] = success ? endpoint[:key] : nil
      current['active_model'] = success ? endpoint[:model] : nil
      current['checked_at'] = Time.current.iso8601
      all[@feature] = current
      @assistant.update_columns(connection_status: all)
    end
  end
end
