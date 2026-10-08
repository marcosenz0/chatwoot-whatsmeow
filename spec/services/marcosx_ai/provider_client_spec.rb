require 'rails_helper'

RSpec.describe MarcosxAi::ProviderClient do
  let(:account) { create(:account) }
  let!(:credential) { account.marcosx_ai_credentials.create!(provider: 'openai', api_key: 'sk-test-secret', enabled: true) }
  let(:client) { described_class.new(account: account, provider: 'openai', model: 'gpt-6.1-sol') }
  let(:messages) { [{ role: 'developer', content: 'Be helpful.' }, { role: 'user', content: 'Hello' }] }
  let(:output) { { output: [{ type: 'message', content: [{ type: 'output_text', text: 'Hello!' }] }], usage: { input_tokens: 10 } } }

  before { stub_request(:post, 'https://api.openai.com/v1/responses').to_return(status: 200, body: output.to_json, headers: { 'Content-Type' => 'application/json' }) }

  it 'uses Responses with developer instructions, reasoning and no incompatible temperature' do
    expect(client.chat(messages: messages, schema: MarcosxAi::ReplyPlan::SCHEMA)).to eq('Hello!')
    expect(a_request(:post, 'https://api.openai.com/v1/responses').with { |request|
      body = JSON.parse(request.body)
      body['store'] == false && body['reasoning'] == { 'effort' => 'medium' } && !body.key?('temperature') &&
        body.dig('text', 'format', 'strict') == true && body.dig('input', 0, 'role') == 'developer'
    }).to have_been_made.once
    expect(client.usage).to eq('input_tokens' => 10)
  end

  it 'uses temperature for a model without reasoning' do
    described_class.new(account: account, provider: 'openai', model: 'gpt-4.1').chat(messages: messages)
    expect(a_request(:post, 'https://api.openai.com/v1/responses').with { |r| JSON.parse(r.body)['temperature'] == 0.7 }).to have_been_made
  end

  it 'refuses a disabled connection' do
    credential.update!(enabled: false)
    expect { client.chat(messages: messages) }.to raise_error(CustomExceptions::MarcosxAi)
    expect(a_request(:post, 'https://api.openai.com/v1/responses')).not_to have_been_made
  end

  it 'does not expose a key echoed by the provider in an error' do
    stub_request(:post, 'https://api.openai.com/v1/responses').to_return(status: 401, body: { error: { message: 'Invalid sk-test-secret' } }.to_json,
                                                                     headers: { 'Content-Type' => 'application/json' })
    expect { client.chat(messages: messages) }.to raise_error { |error|
      expect(error.message).not_to include('sk-test-secret')
      expect(error.class.name).to eq('CustomExceptions::MarcosxAi')
    }
  end

  it 'rejects an incomplete or empty output' do
    stub_request(:post, 'https://api.openai.com/v1/responses').to_return(status: 200, body: { output: [] }.to_json,
                                                                     headers: { 'Content-Type' => 'application/json' })
    expect { client.chat(messages: messages) }.to raise_error(CustomExceptions::MarcosxAi)
  end

  it 'queries available models from the authenticated account' do
    stub_request(:get, 'https://api.openai.com/v1/models').to_return(status: 200, body: { data: [{ id: 'gpt-6.1-sol' }] }.to_json,
                                                                 headers: { 'Content-Type' => 'application/json' })
    expect(client.models).to eq(['gpt-6.1-sol'])
  end

  it 'uses Groq JSON mode and maps developer messages to system messages' do
    account.marcosx_ai_credentials.create!(provider: 'groq', api_key: 'groq-test', enabled: true)
    stub_request(:post, 'https://api.groq.com/openai/v1/chat/completions').to_return(status: 200,
      body: { choices: [{ message: { content: '{}' } }] }.to_json, headers: { 'Content-Type' => 'application/json' })
    described_class.new(account: account, provider: 'groq').chat(messages: messages, schema: MarcosxAi::ReplyPlan::SCHEMA)
    expect(a_request(:post, 'https://api.groq.com/openai/v1/chat/completions').with { |request|
      body = JSON.parse(request.body)
      body['response_format'] == { 'type' => 'json_object' } && body.dig('messages', 0, 'role') == 'system'
    }).to have_been_made.once
  end

  it 'keeps Gemini instructions separate from customer messages and requests structured output' do
    account.marcosx_ai_credentials.create!(provider: 'gemini', api_key: 'gemini-test', enabled: true)
    stub_request(:post, 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent').to_return(status: 200,
      body: { candidates: [{ content: { parts: [{ text: '{}' }] } }] }.to_json, headers: { 'Content-Type' => 'application/json' })
    expect(described_class.new(account: account, provider: 'gemini').chat(messages: messages, schema: MarcosxAi::ReplyPlan::SCHEMA)).to eq('{}')
    expect(a_request(:post, 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent').with { |request|
      body = JSON.parse(request.body)
      body.dig('generationConfig', 'responseMimeType') == 'application/json' && body.dig('systemInstruction', 'parts', 0, 'text') == 'Be helpful.'
    }).to have_been_made.once
  end
end

