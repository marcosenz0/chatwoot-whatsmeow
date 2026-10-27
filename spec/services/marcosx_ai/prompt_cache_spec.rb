require 'rails_helper'

RSpec.describe MarcosxAi::PromptCache do
  let(:account) { create(:account) }
  let(:assistant) { account.marcosx_ai_assistants.create!(name: 'Support', instructions: 'Never invent a price', config: { model: 'gpt-6-luna' }) }
  let(:inbox) { create(:channel_whatsmeow, account: account).inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  def request_for(agent, conversation: nil, context: {})
    messages = MarcosxAi::PromptBuilder.messages(assistant: agent, conversation: conversation, context: context)
    described_class.parameters(messages, account_id: agent.account_id, model: agent.model)
  end

  it 'shares only stable instructions across five independent customer contexts' do
    requests = 5.times.map do |index|
      request_for(assistant, context: { contact: "Private contact #{index}", now: index.to_s, voice: { voice_requested: index.odd? } })
    end
    expect(requests.map { |request| request[:input].first(2) }.uniq.size).to eq(1)
    expect(requests.map { |request| request[:prompt_cache_key] }.uniq.size).to eq(1)
    requests.each_with_index do |request, index|
      expect(request[:input].first(2).to_json).not_to include('Private contact', '"voice_requested":', '"now":')
      expect(request[:input].last[:content]).to include("Private contact #{index}")
      expect(request[:input].to_json.scan('prompt_cache_breakpoint').size).to eq(1)
      expect(request[:prompt_cache_options]).to eq(mode: 'explicit', ttl: '30m')
    end
  end

  it 'keeps scoped catalogs and delivery history after the cache boundary' do
    resource = assistant.resources.create!(account: account, title: 'Restricted item', description: 'Private content', kind: 'link', url: 'https://example.com/private',
                                          audience: 'conversation', conversation: conversation)
    request = request_for(assistant, conversation: conversation)
    expect(request[:input].first(2).to_json).not_to include(resource.title, resource.url, '"contact_history":')
    expect(request[:input].drop(2).to_json).to include(resource.title, 'contact_history')
    other = create(:conversation, account: account, inbox: inbox)
    expect(request_for(assistant, conversation: other)[:input].to_json).not_to include(resource.title, resource.url)
  end

  it 'changes the prefix when instructions change without inserting another customer history' do
    original = request_for(assistant)
    assistant.update!(instructions: 'Never promise a delivery date')
    updated = request_for(assistant)
    expect(updated[:input].first(2)).not_to eq(original[:input].first(2))
    expect(updated[:input][1][:content].first[:text]).to include('Never promise a delivery date')
  end

  it 'separates cache accounting by account and agent rather than contact' do
    other = account.marcosx_ai_assistants.create!(name: 'Other', config: { model: 'gpt-6-luna' })
    expect(request_for(other)[:prompt_cache_key]).not_to eq(request_for(assistant)[:prompt_cache_key])
    messages = MarcosxAi::PromptBuilder.messages(assistant: assistant)
    expect(described_class.parameters(messages, account_id: account.id + 1, model: assistant.model)).not_to have_key(:prompt_cache_key)
  end

  it 'supports long retention and disables all cache writes when the agent opts out' do
    assistant.update!(config: assistant.config.merge(prompt_cache: { enabled: true, ttl: '12h' }))
    expect(request_for(assistant)[:prompt_cache_options]).to eq(mode: 'explicit', ttl: '12h')
    assistant.update!(config: assistant.config.merge(prompt_cache: { enabled: false, ttl: '30m' }))
    request = request_for(assistant)
    expect(request).not_to have_key(:prompt_cache_key)
    expect(request[:input].to_json).not_to include('prompt_cache_breakpoint')
    expect(request[:prompt_cache_options][:mode]).to eq('explicit')
  end

  it 'preserves the original ordering of platform and customer context when caching is disabled' do
    assistant.update!(config: assistant.config.merge(prompt_cache: { enabled: false, ttl: '30m' }))
    messages = MarcosxAi::PromptBuilder.messages(assistant: assistant, context: { contact: 'Client' }, conversation: conversation)
    platform = messages.first[:content]
    expect(messages.map { |message| message[:role] }).to eq(%w[system developer])
    expect(platform.index('Regras de alerta disponíveis')).to be < platform.index('Use recall_context=true')
    expect(platform.index('Use recall_context=true')).to be < platform.index('O responsável cadastrou estes arquivos')
    expect(platform.index('O responsável cadastrou estes arquivos')).to be < platform.index('Chaves Pix cadastradas')
    expect(platform.index('Chaves Pix cadastradas')).to be < platform.index('Quando houver mensagens com current_request=true')
    expect(messages.last[:content]).to include('Client')
  end

  it 'avoids implicit writes for unmarked media, summary and credential requests' do
    request = described_class.parameters([{ role: 'user', content: 'Changing input' }], account_id: account.id, model: 'gpt-6-luna')
    expect(request[:prompt_cache_options]).to eq(mode: 'explicit', ttl: '30m')
    expect(request[:input]).to eq([{ role: 'user', content: 'Changing input' }])
  end

  it 'leaves older models and other providers on their existing prompt path' do
    %w[gpt-4.1 gpt-5.5 gpt-5-mini o3].each do |model|
      assistant.update!(config: assistant.config.merge(model: model))
      expect(request_for(assistant)).not_to have_key(:prompt_cache_options)
      expect(MarcosxAi::PromptBuilder.messages(assistant: assistant).size).to eq(2)
    end
    assistant.update!(config: assistant.config.merge(provider: 'groq', model: 'openai/gpt-oss-120b'))
    expect(MarcosxAi::PromptBuilder.messages(assistant: assistant).map { |message| message[:role] }).to eq(%w[system developer])
  end

  it 'rejects invalid cache configuration without accepting arbitrary provider parameters' do
    [{ enabled: 'true', ttl: '30m' }, { enabled: true, ttl: '24h' }].each do |settings|
      assistant.config = assistant.config.merge(prompt_cache: settings)
      expect { MarcosxAi::ConfigurationValidator.validate!(assistant.resolved_config, account: account) }.to raise_error(ArgumentError)
    end
  end
  it 'does not send OpenAI-specific cache fields to a custom compatible endpoint' do
    account.marcosx_ai_credentials.create!(provider: 'openai', api_key: 'test', enabled: true, api_base: 'https://proxy.example.com/v1')
    messages = MarcosxAi::PromptBuilder.messages(assistant: assistant)
    expect(messages.size).to eq(2)
    request = described_class.parameters(messages, account_id: account.id, model: assistant.model, api_base: 'https://proxy.example.com/v1')
    expect(request).not_to have_key(:prompt_cache_options)
    expect(request).not_to have_key(:prompt_cache_key)
  end

end
