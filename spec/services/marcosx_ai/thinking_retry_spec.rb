require 'rails_helper'

RSpec.describe 'MarcoXIA thinking and bounded quota retries' do
  let(:account) { create(:account) }
  let!(:primary) { account.marcosx_ai_credentials.create!(provider: 'groq', api_key: 'fake-main', enabled: true) }
  let!(:reserve) { account.marcosx_ai_credentials.create!(provider: 'openai', api_key: 'fake-reserve', enabled: true) }
  let(:assistant) do
    account.marcosx_ai_assistants.create!(name: 'QA', config: {
      provider: 'groq', model: 'qwen/qwen3.8-27b', connection_id: primary.id, reasoning_effort: 'none',
      fallback: { enabled: true, provider: 'openai', model: 'gpt-6-luna', connection_id: reserve.id, reasoning_effort: 'high' }
    })
  end
  let(:client) { MarcosxAi::ProviderClient.new(account: account, assistant: assistant, provider: assistant.provider, model: assistant.model) }
  let(:messages) { [{ role: 'user', content: 'The same neutral task' }] }
  let(:groq_url) { 'https://api.groq.com/openai/v1/chat/completions' }
  let(:openai_url) { 'https://api.openai.com/v1/responses' }
  let(:headers) { { 'Content-Type' => 'application/json' } }
  let(:success) { { status: 200, headers: headers, body: { choices: [{ message: { content: 'Recovered' } }] }.to_json } }

  before do
    stub_request(:post, openai_url).to_return(status: 200, headers: headers,
      body: { output: [{ content: [{ type: 'output_text', text: 'Reserve' }] }] }.to_json)
  end

  def quota(delay = nil, message = 'Minute quota')
    { status: 429, headers: headers.merge(delay ? { 'retry-after' => delay } : {}), body: { error: { message: message } }.to_json }
  end

  it 'waits the provider delay, repeats the identical task and schema, and avoids fallback on recovery' do
    requests = []
    stub_request(:post, groq_url).with { |request| requests << JSON.parse(request.body) }.to_return(quota('19.2'), success)
    expect(Kernel).to receive(:sleep).with(20).once
    expect(client.chat(messages: messages, schema: MarcosxAi::ReplyPlan::SCHEMA)).to eq('Recovered')
    expect(requests.size).to eq(2)
    expect(requests.first).to eq(requests.last)
    expect(requests.first['reasoning_effort']).to eq('none')
    expect(assistant.reload.connection_status.dig('chat', 'active_role')).to eq('primary')
    expect(primary.reload.health['state']).to eq('healthy')
    expect(a_request(:post, openai_url)).not_to have_been_made
  end

  it 'falls back with its own thinking level after exhausting two retries, then starts the next task on primary' do
    requests = []
    stub_request(:post, groq_url).with { |request| requests << JSON.parse(request.body) }.to_return(quota('1'), quota('1'), quota('1'), success)
    expect(Kernel).to receive(:sleep).with(1).twice
    expect(client.chat(messages: messages)).to eq('Reserve')
    expect(requests.size).to eq(3)
    expect(requests.uniq.size).to eq(1)
    expect(a_request(:post, openai_url).with { |request| JSON.parse(request.body)['reasoning'] == { 'effort' => 'high' } }).to have_been_made.once
    expect(client.chat(messages: [{ role: 'user', content: 'Next task' }])).to eq('Recovered')
  end

  it 'keeps the reserve when return is off, independently of quota retry being on' do
    assistant.update!(config: assistant.resolved_config.deep_merge(fallback: { retry_primary: false }))
    stub_request(:post, groq_url).to_return(quota('1'))
    expect(Kernel).to receive(:sleep).with(1).twice
    2.times { expect(client.chat(messages: messages)).to eq('Reserve') }
    expect(a_request(:post, groq_url)).to have_been_made.times(3)
    expect(a_request(:post, openai_url)).to have_been_made.twice
  end

  it 'goes immediately to reserve when quota retry is off even when a valid delay is provided' do
    assistant.update!(config: assistant.resolved_config.merge(retry_rate_limits: false))
    stub_request(:post, groq_url).to_return(quota('19.2'))
    expect(Kernel).not_to receive(:sleep)
    expect(client.chat(messages: messages)).to eq('Reserve')
    expect(a_request(:post, groq_url)).to have_been_made.once
  end

  [nil, 'garbage', '-1', 'NaN', 'Infinity', '3600'].each do |delay|
    it "does not wait indefinitely or invent a delay for #{delay.inspect}" do
      stub_request(:post, groq_url).to_return(quota(delay))
      expect(Kernel).not_to receive(:sleep)
      expect(client.chat(messages: messages)).to eq('Reserve')
      expect(a_request(:post, groq_url)).to have_been_made.once
    end
  end

  it 'bounds total sleep at sixty seconds instead of sixty seconds per retry' do
    stub_request(:post, groq_url).to_return(quota('40'))
    expect(Kernel).to receive(:sleep).with(40).once
    expect(client.chat(messages: messages)).to eq('Reserve')
    expect(a_request(:post, groq_url)).to have_been_made.twice
  end

  it 'uses the decimal delay in a Groq error message if Retry-After is absent' do
    stub_request(:post, groq_url).to_return(quota(nil, 'Please try again in 19.2s.'), success)
    expect(Kernel).to receive(:sleep).with(20).once
    expect(client.chat(messages: messages)).to eq('Recovered')
  end

  it 'accepts an HTTP-date Retry-After without retrying before that time' do
    travel_to Time.utc(2026, 11, 3, 12) do
      stub_request(:post, groq_url).to_return(quota(5.seconds.from_now.httpdate), success)
      expect(Kernel).to receive(:sleep).with(5).once
      expect(client.chat(messages: messages)).to eq('Recovered')
    end
  end

  [400, 401, 402, 403, 413, 500, 503].each do |status|
    it "never retries HTTP#{status} just because it contains retry information" do
      stub_request(:post, groq_url).to_return(quota('1').merge(status: status))
      expect(Kernel).not_to receive(:sleep)
      expect(client.chat(messages: messages)).to eq('Reserve')
      expect(a_request(:post, groq_url)).to have_been_made.once
    end
  end

  it 'reports a bounded failure when no reserve is enabled' do
    assistant.update!(config: assistant.resolved_config.deep_merge(fallback: { enabled: false }))
    stub_request(:post, groq_url).to_return(quota('1'))
    expect(Kernel).to receive(:sleep).with(1).twice
    expect { client.chat(messages: messages) }.to raise_error(CustomExceptions::MarcosxAi)
    expect(a_request(:post, openai_url)).not_to have_been_made
  end

  it 'supports quota retry with OpenAI principal and Groq reserve without sending a reasoning setting to a non-thinking model' do
    assistant.update!(config: assistant.resolved_config.deep_merge(provider: 'openai', model: 'gpt-6-luna', connection_id: reserve.id,
      reasoning_effort: 'none', fallback: { provider: 'groq', model: 'llama-3.3-70b-versatile', connection_id: primary.id }))
    stub_request(:post, openai_url).to_return(quota('1'))
    stub_request(:post, groq_url).with { |request| !JSON.parse(request.body).key?('reasoning_effort') }.to_return(success)
    expect(Kernel).to receive(:sleep).with(1).twice
    expect(client.chat(messages: messages)).to eq('Recovered')
  end

  it 'retries incoming transcription with identical audio bytes after rewinding the same file' do
    assistant.update!(config: assistant.resolved_config.deep_merge(transcription: { provider: 'groq', model: 'whisper-large-v3-turbo', connection_id: primary.id }))
    stub_request(:post, 'https://api.groq.com/openai/v1/audio/transcriptions').with { |request| request.body.include?('same-audio') }.to_return(
      quota('1'), { status: 200, headers: headers, body: { text: 'Same speech' }.to_json }
    )
    expect(Kernel).to receive(:sleep).with(1).once
    Tempfile.create(['qa', '.mp3']) do |file|
      file.write('same-audio')
      file.flush
      expect(client.transcribe(file)).to eq('Same speech')
    end
  end

  it 'routes independent image thinking settings instead of inheriting the chat reserve setting' do
    assistant.update!(config: assistant.resolved_config.deep_merge(vision: { provider: 'groq', model: 'qwen/qwen3.8-27b',
      connection_id: primary.id, reasoning_effort: 'low', retry_rate_limits: false,
      fallback: { enabled: true, provider: 'openai', model: 'gpt-6-luna', connection_id: reserve.id, reasoning_effort: 'none' } }))
    stub_request(:post, groq_url).with { |request| JSON.parse(request.body)['reasoning_effort'] == 'low' }.to_return(quota('1'))
    expect(Kernel).not_to receive(:sleep)
    expect(client.chat(messages: messages, purpose: 'media_description')).to eq('Reserve')
    expect(a_request(:post, openai_url).with { |request| JSON.parse(request.body)['reasoning'] == { 'effort' => 'none' } }).to have_been_made.once
  end

  it 'does not retry a successful generation if health storage fails' do
    stub_request(:post, groq_url).to_return(quota('1'), success)
    allow(primary).to receive(:record_health!).and_raise(ActiveRecord::StatementInvalid)
    allow(MarcosxAi::Credential).to receive(:for_provider).and_call_original
    allow(MarcosxAi::Credential).to receive(:for_provider).with(account, 'groq', id: primary.id).and_return(primary)
    expect(Kernel).to receive(:sleep).with(1).once
    expect(client.chat(messages: messages)).to eq('Recovered')
    expect(a_request(:post, groq_url)).to have_been_made.twice
    expect(a_request(:post, openai_url)).not_to have_been_made
  end
end
