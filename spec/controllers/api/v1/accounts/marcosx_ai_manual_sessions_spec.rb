require 'rails_helper'

RSpec.describe 'MarcoXIA manual attendance controls', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:operator) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:assistant) { account.marcosx_ai_assistants.create!(name: 'Support', config: { manual_sessions_enabled: false }) }
  let(:state) { MarcosxAi::ConversationState.for_conversation!(conversation, assistant: assistant) }
  let(:root) { "/api/v1/accounts/#{account.id}/marcosx_ai" }
  let(:endpoint) { "#{root}/assistants/#{assistant.id}/manual_sessions" }

  it 'reports a manually resumed override as active even when the saved group switch is off' do
    state.resume!(manual: true)
    expect(state.metadata['manual_session_override']).to be(true)
    get "#{root}/assistants", headers: admin.create_new_auth_token
    expect(response.parsed_body['assistants'].first).to include('manual_sessions_count' => 1, 'manual_sessions_paused_count' => 0)
    get "#{root}/credentials/health", headers: admin.create_new_auth_token
    expect(response.parsed_body['assistants'].first['manual_sessions_count']).to eq(1)
    get "#{root}/assistants/#{assistant.id}/coverage", params: { manual: true }, headers: admin.create_new_auth_token
    expect(response.parsed_body).to include('mode' => 'individual', 'total' => 1)
    expect(response.parsed_body['conversations'].first['id']).to eq(conversation.display_id)
  end

  it 'pauses and resumes the actual manual group without waking individual pauses or changing general support' do
    state.resume!(manual: true)
    other = create(:conversation, account: account, inbox: inbox)
    paused = MarcosxAi::ConversationState.for_conversation!(other, assistant: assistant)
    paused.resume!(manual: true)
    paused.pause_by_agent!
    original = paused.reload.metadata.except('manual_session_override')
    patch endpoint, params: { enabled: false }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body['assistant']).to include('manual_sessions_count' => 0, 'manual_sessions_paused_count' => 1)
    expect(state.reload.status).to eq('paused_by_agent')
    expect(state.metadata['paused_reason']).to eq('manual_sessions')
    patch endpoint, params: { enabled: true }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body['assistant']['manual_sessions_count']).to eq(1)
    expect(state.reload.status).to eq('active')
    expect(paused.reload.status).to eq('paused_by_agent')
    expect(paused.metadata).to eq(original)
    expect(assistant.reload.auto_response_enabled?).to be(false)
    expect(conversation.messages.outgoing).to be_empty
  end

  it 'also pauses manual contacts with general support on while leaving automatic contacts active' do
    account.marcosx_ai_credentials.create!(provider: 'openai', api_key: 'test', enabled: true)
    assistant.update!(config: assistant.resolved_config.merge(auto_response_enabled: true, manual_sessions_enabled: true))
    assistant.marcosx_ai_inboxes.create!(account: account, inbox: inbox)
    state.resume!(manual: true)
    automatic = MarcosxAi::ConversationState.for_conversation!(create(:conversation, account: account, inbox: inbox), assistant: assistant)
    automatic.resume!
    patch endpoint, params: { enabled: false }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body['assistant']['manual_sessions_count']).to eq(0)
    expect(assistant.reload.auto_response_enabled?).to be(true)
    expect(state.reload.status).to eq('paused_by_agent')
    expect(automatic.reload.status).to eq('active')
    get "#{root}/assistants/#{assistant.id}/coverage", params: { manual: true }, headers: admin.create_new_auth_token
    expect(response.parsed_body).to include('mode' => 'individual', 'total' => 0)
  end

  it 'retains legacy suspended selections but excludes resolved, blocked and individually paused contacts from the active count' do
    state.update!(metadata: { manual_activation: true, conversation_override: true })
    expect(assistant.manual_sessions_summary).to eq(manual_sessions_count: 0, manual_sessions_paused_count: 1)
    patch endpoint, params: { enabled: true }, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['assistant']['manual_sessions_count']).to eq(1)
    state.pause_by_agent!
    expect(assistant.reload.manual_sessions_summary[:manual_sessions_count]).to eq(0)
    state.resume!(manual: true)
    conversation.contact.update!(blocked: true)
    expect(assistant.manual_sessions_summary[:manual_sessions_count]).to eq(0)
    conversation.contact.update!(blocked: false)
    conversation.resolved!
    expect(assistant.manual_sessions_summary[:manual_sessions_count]).to eq(0)
  end

  it 'cancels pending execution tokens and keeps other assistants unchanged' do
    state.resume!(manual: true)
    state.update!(metadata: state.metadata.merge(run_token: 'old', processing: true, pending_response: { messages: ['old'] }, approved_draft: true))
    other = account.marcosx_ai_assistants.create!(name: 'Other')
    original = other.attributes
    patch endpoint, params: { enabled: false }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok), response.body
    expect(state.reload.metadata['run_token']).not_to eq('old')
    expect(state.metadata).not_to have_key('pending_response')
    expect(state.metadata).not_to have_key('approved_draft')
    expect(state.metadata['processing']).to be(false)
    expect(other.reload.attributes).to eq(original)
  end

  it 'clears a delayed individual override without resuming a human pause or a closed group member' do
    state.resume!(manual: true)
    state.update!(status: 'paused_by_human', paused_until: 10.minutes.from_now, metadata: state.metadata.merge(human_wait: true))
    patch endpoint, params: { enabled: false }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok), response.body
    expect(state.reload.status).to eq('paused_by_human')
    expect(state.metadata).not_to have_key('manual_session_override')
    state.update!(status: 'paused_by_agent', metadata: state.metadata.merge(paused_reason: 'manual_sessions'))
    conversation.resolved!
    patch endpoint, params: { enabled: true }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok), response.body
    expect(state.reload.status).to eq('paused_by_agent')
  end

  it 'rejects malformed settings and enforces administrator and account isolation' do
    state.resume!(manual: true)
    original = state.reload.attributes
    [nil, 'false', 0].each do |value|
      patch endpoint, params: { enabled: value }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
    patch endpoint, params: { enabled: false }, headers: operator.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
    other = create(:account).marcosx_ai_assistants.create!(name: 'Other')
    patch "#{root}/assistants/#{other.id}/manual_sessions", params: { enabled: false }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
    expect(state.reload.attributes).to eq(original)
  end
end
