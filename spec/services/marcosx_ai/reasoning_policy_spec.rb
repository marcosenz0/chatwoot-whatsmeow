require 'rails_helper'

RSpec.describe MarcosxAi::ReasoningPolicy do
  {
    ['groq', 'qwen/qwen3.8-27b'] => %w[none default low medium high],
    ['groq', 'openai/gpt-oss-120b'] => %w[low medium high],
    ['groq', 'openai/gpt-oss-20b'] => %w[low medium high],
    ['openai', 'gpt-6-luna'] => %w[none low medium high xhigh max],
    ['openai', 'gpt-6.1-sol'] => %w[low medium high xhigh max],
    ['openai', 'gpt-6-astra'] => %w[low medium high xhigh max],
    ['openai', 'gpt-5.4-2026-03-05'] => %w[none low medium high xhigh],
    ['gemini', 'gemini-2.5-flash'] => %w[default none low medium high],
    ['gemini', 'gemini-2.5-pro'] => %w[default low medium high],
    ['groq', 'llama-3.3-70b-versatile'] => [],
    ['openai', 'gpt-4.1'] => [],
    ['groq', 'whisper-large-v3'] => [],
    ['groq', 'unknown-future-model'] => []
  }.each do |(provider, model), levels|
    it "exposes the provider-specific levels for #{provider}/#{model}" do
      expect(described_class.levels(provider, model)).to eq(levels)
      catalog = MarcosxAi::ModelCatalog.describe(model, provider)
      expect(catalog[:reasoning]).to eq(levels.any?)
      expect(catalog[:reasoning_levels]).to eq(levels)
    end
  end

  it 'resolves a legacy inherited none to a supported level when switching to GPT-OSS' do
    expect(described_class.resolve('groq', 'openai/gpt-oss-120b', 'none')).to eq('medium')
    expect(described_class.resolve('groq', 'qwen/qwen3.8-27b', 'none')).to eq('none')
    expect(described_class.resolve('openai', 'gpt-6-luna', 'none')).to eq('none')
  end

  it 'does not change Gemini provider-default requests and supports a true zero budget for Flash only' do
    expect(described_class.gemini_config('default')).to eq({})
    expect(described_class.gemini_config('none')).to eq(thinkingConfig: { thinkingBudget: 0 })
    expect(described_class.resolve('gemini', 'gemini-2.5-pro', 'none')).to eq('default')
  end
end
