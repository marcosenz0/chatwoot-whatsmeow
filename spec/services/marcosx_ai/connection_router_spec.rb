require 'rails_helper'

RSpec.describe MarcosxAi::ConnectionRouter do
  let(:account) { create(:account) }
  let!(:primary) { account.marcosx_ai_credentials.create!(provider: 'groq', name: 'Principal', api_key: 'primary-secret', enabled: true) }
  let!(:reserve) { account.marcosx_ai_credentials.create!(provider: 'openai', name: 'Reserva', api_key: 'reserve-secret', enabled: true) }
  let(:assistant) do
    account.marcosx_ai_assistants.create!(name: 'Support', config: {
      provider: primary.provider, model: primary.resolved_model, connection_id: primary.id,
      fallback: { enabled: true, provider: reserve.provider, model: reserve.resolved_model, connection_id: reserve.id }
    })
  end
  let(:client) do
    MarcosxAi::ProviderClient.new(account: account, assistant: assistant, provider: assistant.provider, model: assistant.model)
  end
  let(:messages) { [{ role: 'user', content: 'A neutral request' }] }

  it 'uses only the principal when it succeeds and preserves the assistant configuration version' do
    version = assistant.updated_at
    stub_request(:post, 'https://api.groq.com/openai/v1/chat/completions').to_return(
      status: 200, body: { choices: [{ message: { content: 'Primary answer' } }] }.to_json, headers: { 'Content-Type' => 'application/json' }
    )
    expect(client.chat(messages: messages)).to eq('Primary answer')
    expect(assistant.reload.connection_status.dig('chat', 'active_role')).to eq('primary')
    expect(assistant.updated_at).to eq(version)
    expect(primary.reload.health['state']).to eq('healthy')
    expect(a_request(:post, 'https://api.openai.com/v1/responses')).not_to have_been_made
  end

  [401, 402, 403, 429, 500, 503].each do |status|
    it "switches from Groq to OpenAI on provider HTTP#{status} without waiting through Groq retries" do
      stub_request(:post, 'https://api.groq.com/openai/v1/chat/completions').to_return(
        status: status, body: { error: { message: 'Rejected primary-secret' } }.to_json,
        headers: { 'Content-Type' => 'application/json', 'retry-after' => '30' }
      )
      stub_request(:post, 'https://api.openai.com/v1/responses').to_return(
        status: 200, body: { output: [{ content: [{ type: 'output_text', text: 'Reserve answer' }] }] }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
      expect(Kernel).not_to receive(:sleep)
      expect(client.chat(messages: messages)).to eq('Reserve answer')
      expect(client.provider).to eq('openai')
      expect(primary.reload.health).to include('state' => 'error', 'status' => status)
      expect(primary.health.to_json).not_to include('primary-secret')
      expect(reserve.reload.health['state']).to eq('healthy')
      expect(assistant.reload.connection_status.dig('chat', 'active_role')).to eq('fallback')
      expect(a_request(:post, 'https://api.groq.com/openai/v1/chat/completions')).to have_been_made.once
    end
  end

  it 'keeps the reserve in use with automatic return off, even after time passes and the primary key is repaired' do
    assistant.update!(config: assistant.resolved_config.deep_merge(fallback: { retry_primary: false }))
    stub_request(:post, 'https://api.groq.com/openai/v1/chat/completions').to_return(
      status: 401, body: { error: { message: 'Invalid key' } }.to_json, headers: { 'Content-Type' => 'application/json' }
    )
    stub_request(:post, 'https://api.openai.com/v1/responses').to_return(
      status: 200, body: { output: [{ content: [{ type: 'output_text', text: 'Reserve' }] }] }.to_json, headers: { 'Content-Type' => 'application/json' }
    )
    2.times { expect(client.chat(messages: messages)).to eq('Reserve') }
    expect(a_request(:post, 'https://api.groq.com/openai/v1/chat/completions')).to have_been_made.once
    primary.update!(api_key: 'repaired-key', health: {})
    stub_request(:post, 'https://api.groq.com/openai/v1/chat/completions').with(headers: { 'Authorization' => 'Bearer repaired-key' }).to_return(
      status: 200, body: { choices: [{ message: { content: 'Repaired' } }] }.to_json, headers: { 'Content-Type' => 'application/json' }
    )
    travel_to 10.minutes.from_now do
      expect(client.chat(messages: messages)).to eq('Reserve')
    end
    expect(assistant.reload.connection_status.dig('chat', 'active_role')).to eq('fallback')
    expect(a_request(:post, 'https://api.groq.com/openai/v1/chat/completions')).to have_been_made.once
  end

  it 'can reverse to the repaired primary if the currently active reserve fails' do
    assistant.update!(config: assistant.resolved_config.deep_merge(fallback: { retry_primary: false }))
    primary.record_health!(error: CustomExceptions::MarcosxAi.new('Old failure', provider_failure: true, provider_status: 401))
    first = described_class.new(assistant: assistant, feature: 'chat')
    first.send(:record, { key: "credential:#{reserve.id}", provider: reserve.provider, name: reserve.name, role: 'fallback', model: reserve.resolved_model },
               health: { 'state' => 'healthy' }, success: true)
    stub_request(:post, 'https://api.openai.com/v1/responses').to_return(status: 402, body: { error: { message: 'No balance' } }.to_json,
                                                                     headers: { 'Content-Type' => 'application/json' })
    stub_request(:post, 'https://api.groq.com/openai/v1/chat/completions').to_return(status: 200,
      body: { choices: [{ message: { content: 'Primary recovered' } }] }.to_json, headers: { 'Content-Type' => 'application/json' })
    expect(client.chat(messages: messages)).to eq('Primary recovered')
    expect(reserve.reload.health['state']).to eq('error')
    expect(primary.reload.health['state']).to eq('healthy')
  end

  it 'retries the same failed input on the reserve, then starts the next execution on the primary when automatic return is on' do
    primary_body = nil
    reserve_body = nil
    stub_request(:post, 'https://api.groq.com/openai/v1/chat/completions').with { |request|
      primary_body = JSON.parse(request.body)
    }.to_return({ status: 429, body: { error: { message: 'Minute quota' } }.to_json, headers: { 'Content-Type' => 'application/json' } },
                { status: 200, body: { choices: [{ message: { content: 'Next primary answer' } }] }.to_json,
                  headers: { 'Content-Type' => 'application/json' } })
    stub_request(:post, 'https://api.openai.com/v1/responses').with { |request|
      reserve_body = JSON.parse(request.body)
    }.to_return(status: 200, body: { output: [{ content: [{ type: 'output_text', text: 'Same execution on reserve' }] }] }.to_json,
                headers: { 'Content-Type' => 'application/json' })
    expect(client.chat(messages: messages)).to eq('Same execution on reserve')
    expect(primary_body['messages']).to eq(reserve_body['input'])
    expect(client.chat(messages: [{ role: 'user', content: 'A later execution' }])).to eq('Next primary answer')
    expect(assistant.reload.connection_status.dig('chat', 'active_role')).to eq('primary')
    expect(a_request(:post, 'https://api.groq.com/openai/v1/chat/completions')).to have_been_made.twice
    expect(a_request(:post, 'https://api.openai.com/v1/responses')).to have_been_made.once
  end

  it 'can use the reserve again for repeated primary limits while testing the primary on every new execution' do
    stub_request(:post, 'https://api.groq.com/openai/v1/chat/completions').to_return(
      status: 429, body: { error: { message: 'Minute quota', } }.to_json, headers: { 'Content-Type' => 'application/json', 'retry-after' => '60' }
    )
    stub_request(:post, 'https://api.openai.com/v1/responses').to_return(
      status: 200, body: { output: [{ content: [{ type: 'output_text', text: 'Reserve' }] }] }.to_json, headers: { 'Content-Type' => 'application/json' }
    )
    expect(Kernel).not_to receive(:sleep)
    2.times { expect(client.chat(messages: messages)).to eq('Reserve') }
    expect(a_request(:post, 'https://api.groq.com/openai/v1/chat/completions')).to have_been_made.twice
    expect(a_request(:post, 'https://api.openai.com/v1/responses')).to have_been_made.twice
  end

  it 'supports two separately identified Groq connections, even when a test deliberately clones the key' do
    reserve.update!(provider: 'groq', api_key: primary.api_key, model: 'qwen/qwen3.8-27b')
    assistant
    calls = 0
    allow_any_instance_of(MarcosxAi::ProviderClient).to receive(:compatible_response).and_wrap_original do |method, *args|
      calls += 1
      if calls == 1
        raise CustomExceptions::MarcosxAi.new('Simulated primary-account quota', provider_failure: true, provider_status: 429, retry_after: 60)
      end
      'Simulated reserve account answer'
    end
    expect(client.chat(messages: messages)).to eq('Simulated reserve account answer')
    expect(assistant.reload.connection_status.dig('chat', 'active_key')).to eq("credential:#{reserve.id}")
    expect(primary.reload.health['state']).to eq('error')
    expect(reserve.reload.health['state']).to eq('healthy')
  end

  it 'records both failures and raises once when no configured connection works' do
    stub_request(:post, 'https://api.groq.com/openai/v1/chat/completions').to_timeout
    stub_request(:post, 'https://api.openai.com/v1/responses').to_return(status: 401, body: { error: { message: 'Invalid reserve-secret' } }.to_json,
                                                                     headers: { 'Content-Type' => 'application/json' })
    expect { client.chat(messages: messages) }.to raise_error(CustomExceptions::MarcosxAi, I18n.t('marcosx_ai.errors.connections_failed'))
    state = assistant.reload.connection_status['chat']
    expect(state['active_role']).to be_nil
    expect(state['connections'].values.pluck('state')).to eq(%w[error error])
    expect(state.to_json).not_to include('primary-secret', 'reserve-secret')
  end

  it 'does not turn configuration or business errors into another provider request' do
    assistant
    allow_any_instance_of(MarcosxAi::ProviderClient).to receive(:compatible_response).and_raise(CustomExceptions::MarcosxAi, 'A business validation failed')
    expect { client.chat(messages: messages) }.to raise_error(CustomExceptions::MarcosxAi, 'A business validation failed')
    expect(a_request(:post, 'https://api.openai.com/v1/responses')).not_to have_been_made
  end

  it 'does not lose a successful response or call another provider if health persistence fails' do
    allow_any_instance_of(MarcosxAi::Credential).to receive(:record_health!).and_raise(ActiveRecord::StatementInvalid, 'Read-only monitoring store')
    stub_request(:post, 'https://api.groq.com/openai/v1/chat/completions').to_return(
      status: 200, body: { choices: [{ message: { content: 'One successful answer' } }] }.to_json, headers: { 'Content-Type' => 'application/json' }
    )
    expect(client.chat(messages: messages)).to eq('One successful answer')
    expect(a_request(:post, 'https://api.groq.com/openai/v1/chat/completions')).to have_been_made.once
    expect(a_request(:post, 'https://api.openai.com/v1/responses')).not_to have_been_made
  end

  it 'permits a private unsaved preview without locking or rewriting the saved agent configuration' do
    original = assistant.attributes
    assistant.instructions = 'An unsaved private preview'
    stub_request(:post, 'https://api.groq.com/openai/v1/chat/completions').to_return(
      status: 200, body: { choices: [{ message: { content: 'Preview' } }] }.to_json, headers: { 'Content-Type' => 'application/json' }
    )
    expect(client.chat(messages: messages)).to eq('Preview')
    expect(assistant.reload.attributes).to eq(original)
  end

  it 'does not call a reserve when fallback is disabled' do
    assistant.update!(config: assistant.resolved_config.deep_merge(fallback: { enabled: false }))
    stub_request(:post, 'https://api.groq.com/openai/v1/chat/completions').to_timeout
    expect { client.chat(messages: messages) }.to raise_error(CustomExceptions::MarcosxAi)
    expect(a_request(:post, 'https://api.openai.com/v1/responses')).not_to have_been_made
  end

  it 'uses the bounded Groq free-tier default without changing OpenAI reserve defaults' do
    stub_request(:post, 'https://api.groq.com/openai/v1/chat/completions').with { |request|
      JSON.parse(request.body)['max_tokens'] == 768
    }.to_return(status: 429, body: { error: { message: 'Output quota used' } }.to_json, headers: { 'Content-Type' => 'application/json' })
    stub_request(:post, 'https://api.openai.com/v1/responses').with { |request|
      JSON.parse(request.body)['max_output_tokens'] == 8000
    }.to_return(status: 200, body: { output: [{ content: [{ type: 'output_text', text: 'Quota reserve' }] }] }.to_json,
                headers: { 'Content-Type' => 'application/json' })
    expect(client.chat(messages: messages)).to eq('Quota reserve')
  end

  it 'applies separate explicit output budgets to the principal and reserve' do
    assistant.update!(config: assistant.resolved_config.deep_merge(max_output_tokens: 512, fallback: { max_output_tokens: 1200 }))
    stub_request(:post, 'https://api.groq.com/openai/v1/chat/completions').with { |request|
      JSON.parse(request.body)['max_tokens'] == 512
    }.to_return(status: 503, body: { error: { message: 'Unavailable' } }.to_json, headers: { 'Content-Type' => 'application/json' })
    stub_request(:post, 'https://api.openai.com/v1/responses').with { |request|
      JSON.parse(request.body)['max_output_tokens'] == 1200
    }.to_return(status: 200, body: { output: [{ content: [{ type: 'output_text', text: 'Configured reserve' }] }] }.to_json,
                headers: { 'Content-Type' => 'application/json' })
    expect(client.chat(messages: messages)).to eq('Configured reserve')
  end

  %w[groq openai gemini].each do |provider|
    it "does not use a reply cut off by #{provider}'s output budget and tries the reserve" do
      primary.update!(provider: provider)
      reserve.update!(provider: provider == 'openai' ? 'groq' : 'openai')
      assistant
      urls = { 'openai' => 'https://api.openai.com/v1/responses', 'groq' => 'https://api.groq.com/openai/v1/chat/completions',
               'gemini' => 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent' }
      partials = {
        'openai' => { incomplete_details: { reason: 'max_output_tokens' }, output: [{ content: [{ type: 'output_text', text: '{"messages":[' }] }] },
        'groq' => { choices: [{ finish_reason: 'length', message: { content: '{"messages":[' } }] },
        'gemini' => { candidates: [{ finishReason: 'MAX_TOKENS', content: { parts: [{ text: '{"messages":[' }] } }] }
      }
      output = reserve.provider == 'groq' ? { choices: [{ message: { content: 'Complete answer' } }] } :
        { output: [{ content: [{ type: 'output_text', text: 'Complete answer' }] }] }
      stub_request(:post, urls.fetch(provider)).to_return(status: 200, body: partials.fetch(provider).to_json, headers: { 'Content-Type' => 'application/json' })
      stub_request(:post, urls.fetch(reserve.provider)).to_return(status: 200, body: output.to_json, headers: { 'Content-Type' => 'application/json' })
      expect(client.chat(messages: messages)).to eq('Complete answer')
      expect(primary.reload.health['state']).to eq('error')
    end
  end

  it 'treats an empty provider response as a technical failure and tries the reserve' do
    stub_request(:post, 'https://api.groq.com/openai/v1/chat/completions').to_return(
      status: 200, body: { choices: [{ message: { content: '' } }] }.to_json, headers: { 'Content-Type' => 'application/json' }
    )
    stub_request(:post, 'https://api.openai.com/v1/responses').to_return(
      status: 200, body: { output: [{ content: [{ type: 'output_text', text: 'Recovered' }] }] }.to_json, headers: { 'Content-Type' => 'application/json' }
    )
    expect(client.chat(messages: messages)).to eq('Recovered')
    expect(primary.reload.health['state']).to eq('error')
  end

  %w[openai groq gemini].permutation(2).each do |main_provider, backup_provider|
    it "supports #{main_provider} → #{backup_provider} for chat without touching general activation" do
      primary.update!(provider: main_provider)
      reserve.update!(provider: backup_provider)
      assistant
      urls = { 'openai' => 'https://api.openai.com/v1/responses', 'groq' => 'https://api.groq.com/openai/v1/chat/completions',
               'gemini' => 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent' }
      outputs = { 'openai' => { output: [{ content: [{ type: 'output_text', text: 'Chat answer' }] }] },
                  'groq' => { choices: [{ message: { content: 'Chat answer' } }] },
                  'gemini' => { candidates: [{ content: { parts: [{ text: 'Chat answer' }] } }] } }
      stub_request(:post, urls.fetch(main_provider)).to_timeout
      stub_request(:post, urls.fetch(backup_provider)).to_return(status: 200, body: outputs.fetch(backup_provider).to_json,
                                                               headers: { 'Content-Type' => 'application/json' })
      version = assistant.updated_at
      expect(client.chat(messages: messages)).to eq('Chat answer')
      expect(assistant.reload.auto_response_enabled?).to be(false)
      expect(assistant.updated_at).to eq(version)
      expect(assistant.connection_status.dig('chat', 'active_role')).to eq('fallback')
    end
  end

  %w[openai groq gemini].permutation(2).each do |main_provider, backup_provider|
    it "supports #{main_provider} → #{backup_provider} transcription with the same audio bytes" do
      primary.update!(provider: main_provider)
      reserve.update!(provider: backup_provider)
      models = { 'openai' => 'gpt-4o-transcribe', 'groq' => 'whisper-large-v3-turbo', 'gemini' => 'gemini-2.5-flash' }
      assistant.update!(config: assistant.resolved_config.deep_merge(transcription: {
        provider: main_provider, model: models.fetch(main_provider), connection_id: primary.id,
        fallback: { enabled: true, provider: backup_provider, model: models.fetch(backup_provider), connection_id: reserve.id }
      }))
      urls = { 'openai' => 'https://api.openai.com/v1/audio/transcriptions', 'groq' => 'https://api.groq.com/openai/v1/audio/transcriptions',
               'gemini' => 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent' }
      outputs = { 'openai' => { text: 'Same recorded speech' }, 'groq' => { text: 'Same recorded speech' },
                  'gemini' => { candidates: [{ content: { parts: [{ text: 'Same recorded speech' }] } }] } }
      content = 'synthetic-recording-bytes'
      stub_request(:post, urls.fetch(main_provider)).with { |request|
        request.body.include?(main_provider == 'gemini' ? Base64.strict_encode64(content) : content)
      }.to_return(status: 402, body: { error: { message: 'No balance' } }.to_json, headers: { 'Content-Type' => 'application/json' })
      stub_request(:post, urls.fetch(backup_provider)).with { |request|
        request.body.include?(backup_provider == 'gemini' ? Base64.strict_encode64(content) : content)
      }.to_return(status: 200, body: outputs.fetch(backup_provider).to_json, headers: { 'Content-Type' => 'application/json' })
      Tempfile.create(['recording', '.mp3']) do |audio|
        audio.write(content)
        audio.flush
        expect(client.transcribe(audio)).to eq('Same recorded speech')
      end
      expect(assistant.reload.connection_status.dig('transcription', 'active_role')).to eq('fallback')
      expect(assistant.auto_response_enabled?).to be(false)
    end
  end

  %w[openai groq gemini].permutation(2).each do |main_provider, backup_provider|
    it "supports #{main_provider} → #{backup_provider} for image descriptions" do
      primary.update!(provider: main_provider)
      reserve.update!(provider: backup_provider)
      models = { 'openai' => 'gpt-4.1-mini', 'groq' => 'qwen/qwen3.8-27b', 'gemini' => 'gemini-2.5-flash' }
      assistant.update!(config: assistant.resolved_config.deep_merge(vision: {
        provider: main_provider, model: models.fetch(main_provider), connection_id: primary.id,
        fallback: { enabled: true, provider: backup_provider, model: models.fetch(backup_provider), connection_id: reserve.id }
      }))
      urls = { 'openai' => 'https://api.openai.com/v1/responses', 'groq' => 'https://api.groq.com/openai/v1/chat/completions',
               'gemini' => 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent' }
      outputs = { 'openai' => { output: [{ content: [{ type: 'output_text', text: 'Visual answer' }] }] },
                  'groq' => { choices: [{ message: { content: 'Visual answer' } }] },
                  'gemini' => { candidates: [{ content: { parts: [{ text: 'Visual answer' }] } }] } }
      stub_request(:post, urls.fetch(main_provider)).to_return(status: 401, body: { error: { message: 'Failure' } }.to_json,
                                                             headers: { 'Content-Type' => 'application/json' })
      stub_request(:post, urls.fetch(backup_provider)).to_return(status: 200, body: outputs.fetch(backup_provider).to_json,
                                                               headers: { 'Content-Type' => 'application/json' })
      result = client.chat(purpose: 'media_description', messages: [{ role: 'user', content: [
        { type: 'input_text', text: 'Describe this image' }, { type: 'input_image', image_url: 'data:image/jpeg;base64,dGVzdA==' }
      ] }])
      expect(result).to eq('Visual answer')
      expect(assistant.reload.connection_status.dig('vision', 'active_role')).to eq('fallback')
    end
  end
end
