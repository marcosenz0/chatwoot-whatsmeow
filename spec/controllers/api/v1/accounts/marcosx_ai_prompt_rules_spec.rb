require 'rails_helper'

RSpec.describe 'MarcoXIA editable execution instructions', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:operator) { create(:user, account: account, role: :agent) }
  let!(:assistant) { account.marcosx_ai_assistants.create!(name: 'Support', instructions: 'Identity') }
  let(:endpoint) { "/api/v1/accounts/#{account.id}/marcosx_ai/assistants" }
  let(:rules) { { platform: 'My execution rules {{resource_catalog}}', current_request: 'Focus here', memory: 'Compact factual summary' } }
  let(:preset) { { id: 'preset-one', name: 'Preset 1', rules: rules } }

  it 'persists named presets and active texts, renders them and restores defaults while retaining the versions' do
    put "#{endpoint}/#{assistant.id}", params: { assistant: { config: { prompt_rules: rules, prompt_presets: [preset], prompt_preset_id: 'preset-one' } } },
                                        headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok), response.body
    get "#{endpoint}/#{assistant.id}/prompt", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['technical']).to include('My execution rules')
    expect(response.parsed_body['technical']).not_to include('Você é um agente de atendimento')
    expect(response.parsed_body['rules_defaults']['platform']).to include('{{resource_catalog}}', '{{pix_catalog}}')
    put "#{endpoint}/#{assistant.id}", params: { assistant: { config: { prompt_rules: { platform: nil, current_request: nil, memory: nil }, prompt_preset_id: 'system' } } },
                                        headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok), response.body
    expect(assistant.reload.config['prompt_presets'].first['name']).to eq('Preset 1')
    expect(MarcosxAi::PromptRules.custom?(assistant)).to be(false)
  end

  it 'previews unsaved text without changing the agent or activation and supports new-agent defaults' do
    before = assistant.attributes
    post "#{endpoint}/#{assistant.id}/prompt", params: { assistant: { instructions: 'Draft identity', config: { prompt_rules: rules } } },
                                              headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body['technical']).to include('My execution rules')
    expect(response.parsed_body['editable']).to include('Draft identity')
    expect(assistant.reload.attributes).to eq(before)
    expect {
      post "#{endpoint}/prompt", params: { assistant: { name: 'Unsaved', config: {} } }, headers: admin.create_new_auth_token, as: :json
    }.not_to change(MarcosxAi::Assistant, :count)
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body['rules_defaults']['memory']).to eq(MarcosxAi::ConversationContext::MEMORY_PROMPT)
  end

  it 'rejects malformed text atomically and prevents non-admin editing or cross-account previews' do
    before = assistant.attributes
    put "#{endpoint}/#{assistant.id}", params: { assistant: { name: 'Must not apply', config: { prompt_rules: { platform: '{{secret_key}}' } } } },
                                        headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(assistant.reload.attributes).to eq(before)
    post "#{endpoint}/#{assistant.id}/prompt", params: { assistant: { config: { prompt_rules: rules } } }, headers: operator.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
    other = create(:account).marcosx_ai_assistants.create!(name: 'Other')
    post "#{endpoint}/#{other.id}/prompt", params: { assistant: { config: {} } }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
  end
end
