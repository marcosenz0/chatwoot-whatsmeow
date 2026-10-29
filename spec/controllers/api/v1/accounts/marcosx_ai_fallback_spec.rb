require 'rails_helper'

RSpec.describe 'MarcoXIA named fallback connections API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:operator) { create(:user, account: account, role: :agent) }
  let(:endpoint) { "/api/v1/accounts/#{account.id}/marcosx_ai" }
  let!(:primary) { account.marcosx_ai_credentials.create!(provider: 'groq', name: 'Main account', api_key: 'private-main-key', enabled: true) }
  let!(:reserve) { account.marcosx_ai_credentials.create!(provider: 'groq', name: 'Reserve account', api_key: 'private-reserve-key', enabled: true) }
  let!(:assistant) do
    account.marcosx_ai_assistants.create!(name: 'Support', config: {
      provider: 'groq', model: 'qwen/qwen3.8-27b', connection_id: primary.id,
      fallback: { enabled: true, provider: 'groq', model: 'qwen/qwen3.8-27b', connection_id: reserve.id }
    })
  end

  it 'saves a third account without replacing either existing key and never returns secrets' do
    expect {
      post "#{endpoint}/credentials", params: { credential: { provider: 'groq', name: 'Another account', api_key: 'third-secret' } },
                                     headers: admin.create_new_auth_token, as: :json
    }.to change(account.marcosx_ai_credentials, :count).by(1)
    expect(response).to have_http_status(:ok), response.body
    expect(primary.reload.api_key).to eq('private-main-key')
    expect(reserve.reload.api_key).to eq('private-reserve-key')
    expect(response.body).not_to include('third-secret')
  end

  it 'requires a separate key for a newly named account instead of silently copying the main key' do
    expect {
      post "#{endpoint}/credentials", params: { credential: { provider: 'groq', name: 'Unconfigured reserve', api_key: '' } },
                                     headers: admin.create_new_auth_token, as: :json
    }.not_to change(account.marcosx_ai_credentials, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'saves independent principal and reserve references for chat, vision and transcription' do
    settings = {
      connection_id: primary.id, fallback: { enabled: true, provider: 'groq', connection_id: reserve.id, model: 'openai/gpt-oss-120b' },
      vision: { provider: 'groq', model: 'qwen/qwen3.8-27b', connection_id: primary.id,
                fallback: { enabled: true, provider: 'groq', model: 'qwen/qwen3.8-27b', connection_id: reserve.id } },
      transcription: { provider: 'groq', model: 'whisper-large-v3-turbo', connection_id: primary.id,
                       fallback: { enabled: true, provider: 'groq', model: 'whisper-large-v3', connection_id: reserve.id } }
    }
    put "#{endpoint}/assistants/#{assistant.id}", params: { assistant: { config: settings } }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok), response.body
    config = assistant.reload.resolved_config
    expect(config[:fallback][:model]).to eq('openai/gpt-oss-120b')
    expect(config[:vision][:fallback][:connection_id]).to eq(reserve.id)
    expect(config[:transcription][:fallback][:model]).to eq('whisper-large-v3')
    expect(config[:auto_response_enabled]).to be(false)
  end

  it 'rejects the exact same connection as principal and reserve without modifying the agent' do
    before = assistant.attributes
    put "#{endpoint}/assistants/#{assistant.id}", params: { assistant: { config: { fallback: { connection_id: primary.id } } } },
                                                headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(assistant.reload.attributes).to eq(before)
  end

  it 'rejects another account connection in any slot' do
    foreign = create(:account).marcosx_ai_credentials.create!(provider: 'groq', api_key: 'other-account-secret')
    put "#{endpoint}/assistants/#{assistant.id}", params: { assistant: { config: { vision: { connection_id: foreign.id } } } },
                                                headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(assistant.reload.resolved_config[:vision][:connection_id]).to be_nil
    post "#{endpoint}/credentials/test", params: { provider: 'groq', credential_id: foreign.id }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).not_to include('other-account-secret')
  end

  it 'rejects a connection whose provider does not match the selected provider' do
    put "#{endpoint}/assistants/#{assistant.id}", params: { assistant: { config: { fallback: { provider: 'openai', connection_id: reserve.id } } } },
                                                headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'allows general support when the configured reserve is usable and the main connection is disabled' do
    primary.update!(enabled: false)
    put "#{endpoint}/assistants/#{assistant.id}", params: { assistant: { config: { auto_response_enabled: true } } },
                                                headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok), response.body
    expect(assistant.reload.auto_response_enabled?).to be(true)
  end

  it 'protects a referenced reserve from deletion' do
    delete "#{endpoint}/credentials/#{reserve.id}", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:unprocessable_entity)
    expect(reserve.reload.api_key).to eq('private-reserve-key')
  end

  it 'reports both connection states without returning keys, and only to administrators' do
    primary.record_health!(error: CustomExceptions::MarcosxAi.new('Quota reached', provider_failure: true, provider_status: 429))
    reserve.record_health!
    get "#{endpoint}/credentials/health", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body['credentials']).to include(hash_including('id' => primary.id, 'health' => hash_including('state' => 'error')))
    expect(response.parsed_body['credentials']).to include(hash_including('id' => reserve.id, 'health' => hash_including('state' => 'healthy')))
    expect(response.body).not_to include('private-main-key', 'private-reserve-key')
    get "#{endpoint}/credentials/health", headers: operator.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
  end

  it 'clears a failure only for the connection whose key is repaired' do
    [primary, reserve].each { |item| item.record_health!(error: CustomExceptions::MarcosxAi.new('Invalid key', provider_failure: true, provider_status: 401)) }
    put "#{endpoint}/credentials/#{primary.id}", params: { credential: { api_key: 'repaired-secret' } }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok), response.body
    expect(primary.reload.health).to eq({})
    expect(reserve.reload.health['state']).to eq('error')
    expect(response.body).not_to include('repaired-secret')
  end

  it 'tests the selected same-provider account and updates its health without using a fallback' do
    stub_request(:post, 'https://api.groq.com/openai/v1/chat/completions')
      .with(headers: { 'Authorization' => 'Bearer private-reserve-key' })
      .to_return(status: 200, body: { choices: [{ message: { content: 'OK' } }] }.to_json, headers: { 'Content-Type' => 'application/json' })
    post "#{endpoint}/credentials/test", params: { provider: 'groq', credential_id: reserve.id, model: 'qwen/qwen3.8-27b' },
                                        headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok), response.body
    expect(reserve.reload.health['state']).to eq('healthy')
    expect(primary.reload.health).to eq({})
  end
end
