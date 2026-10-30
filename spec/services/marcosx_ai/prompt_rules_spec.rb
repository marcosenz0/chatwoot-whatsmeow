require 'rails_helper'

RSpec.describe MarcosxAi::PromptRules do
  let(:account) { create(:account) }
  let(:assistant) { account.marcosx_ai_assistants.create!(name: 'Support', instructions: 'Custom identity', config: { model: 'gpt-6-luna' }) }
  let(:inbox) { create(:channel_whatsmeow, account: account).inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  it 'replaces platform text, current-request focus and memory instructions without appending the originals' do
    assistant.update!(config: assistant.config.merge(prompt_rules: { platform: 'My execution rules', current_request: 'My focus', memory: 'My summary' }))
    prompt = MarcosxAi::PromptBuilder.messages(assistant: assistant).first[:content]
    expect(prompt).to eq('My execution rules')
    history = [{ role: 'user', content: { message_id: 1, text: 'Hello', current_request: true }.to_json }]
    focused = MarcosxAi::PromptBuilder.focused_history(history, assistant: assistant)
    expect(focused[-2][:content]).to eq('My focus')
    expect(described_class.value(assistant, :memory, MarcosxAi::ConversationContext::MEMORY_PROMPT)).to eq('My summary')
  end

  it 'restores the exact system default and retains named presets' do
    original = MarcosxAi::PromptBuilder.messages(assistant: assistant).to_json
    preset = { id: 'preset-1', name: 'My preset', rules: { platform: 'My rules', current_request: 'My focus', memory: 'My summary' } }
    assistant.update!(config: assistant.config.merge(prompt_rules: preset[:rules], prompt_presets: [preset], prompt_preset_id: preset[:id]))
    assistant.update!(config: assistant.config.merge(prompt_rules: { platform: nil, current_request: nil, memory: nil }, prompt_preset_id: 'system'))
    expect(MarcosxAi::PromptBuilder.messages(assistant: assistant).to_json).to eq(original)
    expect(assistant.reload.config['prompt_presets'].first['name']).to eq('My preset')
    expect(described_class.defaults(assistant)[:platform]).to include('{{resource_catalog}}', '{{pix_catalog}}', '{{alert_rules}}')
  end

  it 'keeps scoped catalog data after the cache boundary and substitutes values only once' do
    resource = assistant.resources.create!(account: account, title: 'Private {{pix_catalog}}', description: 'Scoped test resource',
                                          kind: 'link', url: 'https://example.com/item',
                                          audience: 'conversation', conversation: conversation)
    assistant.update!(config: assistant.config.merge(prompt_rules: { platform: 'Rules {{resource_catalog}}; Pix {{pix_catalog}}' }))
    messages = MarcosxAi::PromptBuilder.messages(assistant: assistant, conversation: conversation)
    expect(messages.first(2).to_json).not_to include(resource.title, 'https://example.com/item', 'contact_history')
    expect(messages.drop(2).to_json).to include(resource.title, 'contact_history')
    other = create(:conversation, account: account, inbox: inbox)
    expect(MarcosxAi::PromptBuilder.messages(assistant: assistant, conversation: other).to_json).not_to include(resource.title)
    rendered = described_class.render('{{resource_catalog}}', assistant: assistant, conversation: conversation)
    expect(rendered).to include('Private {{pix_catalog}}')
  end

  it 'uses new catalog data without changing a saved preset and preserves explicit empty overrides' do
    assistant.update!(config: assistant.config.merge(provider: 'groq', model: 'qwen/qwen3.8-27b',
                                                     prompt_rules: { platform: '{{resource_catalog}}', current_request: '', memory: '' }))
    before = MarcosxAi::PromptBuilder.messages(assistant: assistant).first[:content]
    assistant.resources.create!(account: account, title: 'New file', description: 'New test resource', kind: 'link', url: 'https://example.com/new')
    after = MarcosxAi::PromptBuilder.messages(assistant: assistant).first[:content]
    expect(before).not_to include('New file')
    expect(after).to include('New file')
    expect(described_class.value(assistant, :memory, 'default')).to eq('')
  end

  it 'rejects malformed presets, duplicate IDs, reserved IDs, unknown markers and excessive text' do
    invalid = [
      { prompt_rules: { platform: '{{api_key}}' } },
      { prompt_rules: { platform: 'a' * 30_001 } },
      { prompt_rules: { memory: '{{resource_catalog}}' } },
      { prompt_rules: { platform: false } },
      { prompt_presets: [{ id: 'system', name: 'Override', rules: { platform: '', current_request: '', memory: '' } }] },
      { prompt_presets: [{ id: 'a', name: '', rules: {} }] },
      { prompt_preset_id: 'missing' }
    ]
    invalid.each do |change|
      settings = assistant.resolved_config.deep_merge(change.with_indifferent_access)
      expect { described_class.validate!(settings) }.to raise_error(ArgumentError)
    end
    rules = { platform: '', current_request: '', memory: '' }
    duplicate = { id: 'same', name: 'Example', rules: rules }
    expect { described_class.validate!(assistant.resolved_config.merge(prompt_presets: [duplicate, duplicate])) }.to raise_error(ArgumentError)
  end
end
