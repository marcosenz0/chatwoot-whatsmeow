require 'rails_helper'

RSpec.describe 'MarcoXIA vision configuration API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:assistant) { account.marcosx_ai_assistants.create!(name: 'Support', instructions: 'Preserve me') }
  let(:endpoint) { "/api/v1/accounts/#{account.id}/marcosx_ai" }
  let!(:hook) do
    create(:integrations_hook, account: account, app_id: 'audio_transcription',
                               settings: { provider: 'groq', groq_api_key: 'private-groq-key' })
  end

  it 'reports the reused integration connection without leaking its key' do
    get "#{endpoint}/preferences", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['credentials']).to include(hash_including('provider' => 'groq', 'configured' => true, 'source' => 'integration'))
    expect(response.body).not_to include('private-groq-key')
  end

  it 'saves the chat and image models together and enables or disables general support without losing other settings' do
    body = { assistant: { config: {
      provider: 'groq', model: 'qwen/qwen3.8-27b', auto_response_enabled: true,
      vision: { provider: 'groq', model: 'qwen/qwen3.8-27b', max_dimension: 1024, video_frames: 3, video_interval_seconds: 4, instructions: 'Read visible text' }
    } } }
    put "#{endpoint}/assistants/#{assistant.id}", params: body, as: :json, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok), response.body
    put "#{endpoint}/assistants/#{assistant.id}", params: { assistant: { config: { model: 'openai/gpt-oss-120b', auto_response_enabled: false } } },
                                                    as: :json, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok), response.body
    expect(assistant.reload.resolved_config).to include('model' => 'openai/gpt-oss-120b', 'auto_response_enabled' => false)
    expect(assistant.resolved_config[:vision]).to include('model' => 'qwen/qwen3.8-27b', 'max_dimension' => 1024)
    expect(assistant.instructions).to eq('Preserve me')
  end

  it 'rejects malformed image configuration without changing the agent' do
    before = assistant.attributes
    put "#{endpoint}/assistants/#{assistant.id}", params: { assistant: { config: { vision: { video_frames: 'three' } } } },
                                                    as: :json, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:unprocessable_entity)
    expect(assistant.reload.attributes).to eq(before)
  end

  it 'preserves an existing integration key if its connection endpoint is explicitly saved without a new password' do
    post "#{endpoint}/credentials", params: { credential: { provider: 'groq', api_key: '', api_base: 'https://api.groq.com/openai/v1' } },
                                   as: :json, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok), response.body
    expect(account.marcosx_ai_credentials.find_by!(provider: 'groq').api_key).to eq('private-groq-key')
    expect(response.body).not_to include('private-groq-key')
  end
end
