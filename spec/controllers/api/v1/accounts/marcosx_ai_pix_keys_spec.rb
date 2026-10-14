require 'rails_helper'

RSpec.describe 'MarcoXIA Pix keys API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:assistant) { account.marcosx_ai_assistants.create!(name: 'Support') }
  let(:endpoint) { "/api/v1/accounts/#{account.id}/marcosx_ai/assistants/#{assistant.id}/pix_keys" }
  let(:payload) { { title: 'Main', key_type: 'EMAIL', key: 'pix@example.com', merchant_name: 'Test holder', description: 'Direct purchase', enabled: true } }

  it 'registers multiple keys, normalizes values and enforces two active slots without activating the agent' do
    post endpoint, params: { pix_key: payload }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:created), response.body
    first = response.parsed_body['pix_keys'].first
    expect(first).to include('enabled' => true, 'primary' => true, 'key' => 'pix@example.com')
    post endpoint, params: { pix_key: payload.merge(key: 'other@example.com') }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:created)
    second = response.parsed_body['pix_keys'].last
    post endpoint, params: { pix_key: payload.merge(key: 'third@example.com') }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(assistant.pix_keys.count).to eq(2)
    post endpoint, params: { pix_key: payload.merge(key: 'third@example.com', enabled: false) }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:created)
    third = response.parsed_body['pix_keys'].last
    patch "#{endpoint}/#{third['id']}", params: { pix_key: { enabled: true } }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    patch "#{endpoint}/#{second['id']}", params: { pix_key: { primary: true } }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['pix_keys'].first['id']).to eq(second['id'])
    delete "#{endpoint}/#{second['id']}", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['pix_keys'].first).to include('id' => first['id'], 'primary' => true)
    patch "#{endpoint}/#{first['id']}", params: { pix_key: { enabled: false } }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(assistant.pix_keys.available).to be_empty
    expect(assistant.reload.auto_response_enabled?).to be(false)
  end

  it 'rejects malformed keys, duplicates and booleans of the wrong type with 422' do
    post endpoint, params: { pix_key: payload.merge(key_type: 'CPF', key: '11111111111') }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    post endpoint, params: { pix_key: payload.merge(enabled: 'true') }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    post endpoint, params: { pix_key: payload }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:created)
    post endpoint, params: { pix_key: payload.merge(key: 'PIX@EXAMPLE.COM', enabled: false) }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(assistant.pix_keys.count).to eq(1)
  end

  it 'allows multiple keys of the same type and keeps agent and account scopes private' do
    post endpoint, params: { pix_key: payload.merge(key_type: 'PHONE', key: '(11) 99999-9999') }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:created)
    first = response.parsed_body['pix_keys'].first
    expect(first['key']).to eq('+5511999999999')
    post endpoint, params: { pix_key: payload.merge(key_type: 'PHONE', key: '(11) 98888-8888') }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:created)
    get endpoint, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
    other = account.marcosx_ai_assistants.create!(name: 'Other')
    patch endpoint.sub("/#{assistant.id}/pix_keys", "/#{other.id}/pix_keys") + "/#{first['id']}",
          params: { pix_key: { enabled: false } }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
    foreign = create(:account).marcosx_ai_assistants.create!(name: 'Foreign')
    get endpoint.sub("/#{assistant.id}/pix_keys", "/#{foreign.id}/pix_keys"), headers: admin.create_new_auth_token
    expect(response).to have_http_status(:not_found)
  end
end
