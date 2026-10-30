class MarcosxAi::ModelCatalog
  SUGGESTED = {
    'openai' => %w[gpt-6.1-sol gpt-6-astra gpt-6-luna gpt-5.4 gpt-4.1 gpt-4.1-mini gpt-4o],
    'groq' => %w[qwen/qwen3.8-27b openai/gpt-oss-120b openai/gpt-oss-20b llama-3.3-70b-versatile],
    'gemini' => %w[gemini-2.5-pro gemini-2.5-flash]
  }.freeze

  def self.for_provider(account:, provider:, refresh: false, credential_id: nil)
    credential = MarcosxAi::Credential.for_provider(account, provider, id: credential_id)
    return { models: SUGGESTED.fetch(provider).map { |id| describe(id, provider) }, verified: false } unless credential&.configured?

    key = ['marcosx-ai-models', account.id, provider, Digest::SHA256.hexdigest(credential.api_key), credential.resolved_api_base]
    Rails.cache.delete(key) if refresh
    ids = Rails.cache.fetch(key, expires_in: 30.minutes) do
      MarcosxAi::ProviderClient.new(account: account, provider: provider, credential: credential).models
    end
    ids = ids.select { |id| conversational?(id, provider) }.sort_by { |id| [SUGGESTED.fetch(provider).index(id) || 100, id] }
    { models: ids.map { |id| describe(id, provider) }, verified: true }
  end

  def self.conversational?(id, provider)
    return id.start_with?('gemini-') && !id.match?(/embedding|image|tts|robotics|live|computer|audio/) if provider == 'gemini'
    return !id.match?(/whisper|guard|tts|embed|playai|orpheus/) if provider == 'groq'

    id.match?(/\A(gpt-[4-9]|o[3-9])/) && !id.match?(/audio|realtime|transcrib|tts|image|codex|search|deep-research|instruct|pro(?:-|$)/)
  end

  def self.describe(id, provider)
    {
      id: id, name: id,
      recommended: id == SUGGESTED.fetch(provider).first,
      vision: provider != 'groq' || id.match?(/llama-4|vision|qwen3\.[68]-27b|qwen3-vl|muse-spark/),
      reasoning: (provider == 'openai' && id.match?(/\A(gpt-[5-9]|o[3-9])/)) ||
        (provider == 'groq' && id.match?(/gpt-oss|qwen3\.[68]-27b/)),
      files: provider != 'groq',
      structured_outputs: provider == 'groq' && %w[qwen/qwen3.8-27b openai/gpt-oss-120b openai/gpt-oss-20b].include?(id),
      max_images: provider == 'groq' && id.match?(/qwen3\.[68]-27b/) ? 3 : 6
    }
  end
end
