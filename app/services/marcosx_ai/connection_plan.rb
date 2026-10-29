class MarcosxAi::ConnectionPlan
  def initialize(assistant:, feature:)
    @assistant = assistant
    @feature = feature
  end

  def endpoints
    config = @assistant.resolved_config
    settings = @feature == 'chat' ? config : config.fetch(@feature)
    primary = settings.slice(:provider, :model, :connection_id)
    if primary[:provider] == 'agent'
      primary = config.slice(:provider, :model, :connection_id)
      primary[:model] = default_transcription_model(primary[:provider]) if @feature == 'transcription'
    end
    fallback = settings[:fallback]
    targets = [primary.merge(role: 'primary')]
    targets << fallback.slice(:provider, :model, :connection_id).merge(role: 'fallback') if fallback[:enabled]
    targets.filter_map do |target|
      next if @feature == 'vision' && !MarcosxAi::ModelCatalog.describe(target[:model], target[:provider])[:vision]

      credential = MarcosxAi::Credential.for_provider(@assistant.account, target[:provider], id: target[:connection_id])
      target.merge(credential: credential, key: credential&.id ? "credential:#{credential.id}" : "integration:#{target[:provider]}",
                   name: credential&.name || 'Principal')
    end
  end

  def default_transcription_model(provider)
    { 'openai' => 'gpt-4o-transcribe', 'groq' => 'whisper-large-v3-turbo', 'gemini' => 'gemini-2.5-flash' }.fetch(provider)
  end
end
