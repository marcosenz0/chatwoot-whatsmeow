require 'rails_helper'

RSpec.describe 'MarcoXIA operations API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: admin) }
  let(:assistant) { account.marcosx_ai_assistants.create!(name: 'Support', instructions: 'Be attentive') }
  let(:state) { MarcosxAi::ConversationState.for_conversation!(conversation, assistant: assistant) }
  let(:endpoint) { "/api/v1/accounts/#{account.id}/marcosx_ai" }
  let(:memory_endpoint) { "#{endpoint}/conversations/#{conversation.display_id}/memory" }

  it 'saves editable instructions and generic alert rules without enabling general support' do
    settings = { editorial_instructions: 'Speak warmly', memory_mode: 'summary_recent',
                 notifications: { user_ids: [admin.id], whatsapp_numbers: [], inbox_id: nil },
                 alert_rules: [{ id: 'help', name: 'Help', description: 'Needs a person', action: 'pause', message: '{reason}' }] }
    put "#{endpoint}/assistants/#{assistant.id}", params: { assistant: { config: settings } }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok), response.body
    expect(assistant.reload.resolved_config[:auto_response_enabled]).to be(false)
    get "#{endpoint}/assistants/#{assistant.id}/prompt", headers: admin.create_new_auth_token
    expect(response.parsed_body['editable']).to include('Speak warmly')
    expect(response.parsed_body['technical']).to include('JSON')
  end

  it 'rejects cross-account recipients and invalid rule actions atomically' do
    other = create(:user)
    original = assistant.config
    put "#{endpoint}/assistants/#{assistant.id}", params: { assistant: { config: {
      notifications: { user_ids: [other.id], whatsapp_numbers: [], inbox_id: nil }
    } } }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(assistant.reload.config).to eq(original)
    put "#{endpoint}/assistants/#{assistant.id}", params: { assistant: { config: {
      alert_rules: [{ id: 'help', name: 'Help', description: 'Help', action: 'execute', message: '' }]
    } } }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'denies editing recipients and reading memory outside the operator inboxes' do
    state.update!(metadata: { conversation_summary: 'Protected summary' })
    get memory_endpoint, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to include('Protected summary')
    get "#{endpoint}/assistants/notification_options", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
  end

  it 'updates the recent window and cancels an obsolete pending reply' do
    state.update!(metadata: { run_token: 'old', pending_response: { messages: ['Obsolete'] }, processing: true })
    put memory_endpoint, params: { memory: { mode: 'summary_recent', recent_limit: 20 } }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body['memory']).to include('mode' => 'summary_recent', 'recent_limit' => 20)
    expect(state.reload.metadata).not_to have_key('pending_response')
    expect(state.metadata['run_token']).not_to eq('old')
  end

  it 'requires explicit same-account channel approval and revokes pending context on removal' do
    state
    other = create(:conversation)
    other.update_column(:display_id, 999_999)
    post "#{memory_endpoint}/link", params: { memory: { conversation_id: other.display_id } }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
    source = create(:conversation, account: account, inbox: create(:inbox, account: account))
    post "#{memory_endpoint}/link", params: { memory: { conversation_id: source.display_id } }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body['memory']['links'].pluck('id')).to eq([source.display_id])
    state.reload.update!(metadata: state.metadata.merge('run_token' => 'linked', 'pending_response' => { 'messages' => ['Old context'] }))
    delete "#{memory_endpoint}/unlink", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok), response.body
    expect(state.reload.metadata).not_to have_key('approved_context_links')
    expect(state.metadata).not_to have_key('pending_response')
    expect(state.metadata['run_token']).not_to eq('linked')
  end

  it 'resolves an alert without reactivating the agent and isolates other accounts' do
    state.wait_for_human!(reason: 'Help')
    alert = MarcosxAi::Alert.create!(account: account, conversation: conversation, assistant: assistant,
                                     rule_id: 'help', name: 'Help', action: 'pause')
    put "#{endpoint}/alerts/#{alert.id}", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok), response.body
    expect(alert.reload.status).to eq('resolved')
    expect(state.reload.status).to eq('awaiting_human')
    get "/api/v1/accounts/#{create(:account).id}/marcosx_ai/alerts", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
  end

  it 'simulates missed calls, alerts and pause without deliveries or conversation changes' do
    state
    assistant.update!(config: { pause_on_handoff: true, alert_rules: [{ id: 'help', name: 'Help', description: 'Needs a person', action: 'pause' }] })
    client = instance_double(MarcosxAi::ProviderClient, usage: {})
    allow(MarcosxAi::ProviderClient).to receive(:new).and_return(client)
    allow(client).to receive(:chat).and_return({ messages: ['I will ask for help'], reaction: nil, reaction_message_id: nil,
                                               handoff: true, handoff_reason: 'Help', alert_rule_ids: ['help'], recall_context: false }.to_json)
    expect {
      post "#{endpoint}/assistants/#{assistant.id}/playground", params: { assistant: { message: 'Can you help?', event: 'missed_call' } },
           headers: admin.create_new_auth_token, as: :json
    }.not_to change(MarcosxAi::Alert, :count)
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body.dig('simulation', 'paused')).to be(true)
    expect(state.reload.status).to eq('active')
    expect(conversation.messages.count).to eq(0)
  end

  it 'tests notifications only against explicit saved recipients without pausing the conversation' do
    state
    assistant.update!(config: { notifications: { user_ids: [admin.id], whatsapp_numbers: [], inbox_id: nil } })
    expect {
      post "#{endpoint}/assistants/#{assistant.id}/test_notification", params: { conversation_id: conversation.display_id },
           headers: admin.create_new_auth_token, as: :json
    }.to change(MarcosxAi::AlertDelivery, :count).by(1)
    expect(response).to have_http_status(:accepted), response.body
    expect(response.parsed_body.dig('alert', 'status')).to eq('resolved')
    expect(state.reload.status).to eq('active')
    expect(MarcosxAi::AlertDelivery.last.recipient).to eq(admin.id.to_s)
  end
end
