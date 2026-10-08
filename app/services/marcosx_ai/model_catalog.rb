class MarcosxAi::ModelCatalog
  SUGGESTED = {
    'openai' => %w[gpt-6.1-sol gpt-6-astra gpt-6-luna gpt-5.4 gpt-4.1 gpt-4.1-mini gpt-4o],
    'groq' => %w[llama-3.3-70b-versatile openai/gpt-oss-120b],
    'gemini' => %w[gemini-2.5-pro gemini-2.5-flash]
  }.freeze

  def self.for_provider(account:, provider:, refresh: false)
    credential = account.marcosx_ai_credentials.find_by(provider: provider)
    return { models: SUGGESTED.fetch(provider).map { |id| describe(id, provider) }, verified: false } unless credential&.configured?

    key = ['marcosx-ai-models', credential.id, credential.updated_at.to_i]
    Rails.cache.delete(key) if refresh
    ids = Rails.cache.fetch(key, expires_in: 30.minutes) do
      MarcosxAi::ProviderClient.new(account: account, provider: provider).models
    end
    ids = ids.select { |id| conversational?(id, provider) }.sort_by { |id| [SUGGESTED.fetch(provider).index(id) || 100, id] }
    { models: ids.map { |id| describe(id, provider) }, verified: true }
  end

  def self.conversational?(id, provider)
    return id.start_with?('gemini-') && !id.match?(/embedding|image|tts|robotics|live|computer|audio/) if provider == 'gemini'
    return !id.match?(/whisper|guard|tts|embed|playai/) if provider == 'groq'

    id.match?(/\A(gpt-[4-9]|o[3-9])/) && !id.match?(/audio|realtime|transcrib|tts|image|codex|search|deep-research|instruct|pro(?:-|$)/)
  end

  def self.describe(id, provider)
    {
      id: id, name: id,
      recommended: id == SUGGESTED.fetch(provider).first,
      vision: provider != 'groq' || id.match?(/llama-4|vision/),
      reasoning: provider == 'openai' && id.match?(/\A(gpt-[5-9]|o[3-9])/),
      files: provider != 'groq'
    }
  end
end
