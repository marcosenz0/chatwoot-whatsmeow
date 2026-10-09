require 'rails_helper'

RSpec.describe 'MarcoXIA API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:endpoint) { "/api/v1/accounts/#{account.id}/marcosx_ai" }
  let!(:credential) { account.marcosx_ai_credentials.create!(provider: 'openai', api_key: 'test-secret', enabled: true) }
  let!(:assistant) { account.marcosx_ai_assistants.create!(name: 'Support', instructions: 'Be attentive') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  it 'creates a single agent linked to multiple inboxes' do
    another_inbox = create(:inbox, account: account)
    post "#{endpoint}/assistants", params: { assistant: { name: 'Shared', inbox_ids: [inbox.id, another_inbox.id] } }, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['assistant']['inbox_ids']).to contain_exactly(inbox.id, another_inbox.id)
  end

  it 'rejects inboxes from another account atomically' do
    other = create(:inbox)
    expect {
      post "#{endpoint}/assistants", params: { assistant: { name: 'Bad', inbox_ids: [inbox.id, other.id] } }, headers: admin.create_new_auth_token
    }.not_to change(MarcosxAi::Assistant, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'keeps the existing configuration when updating one setting' do
    assistant.update!(config: { max_message_parts: 5, split_messages: true })
    put "#{endpoint}/assistants/#{assistant.id}", params: { assistant: { config: { response_delay_seconds: 20 } } }, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(assistant.reload.resolved_config).to include('max_message_parts' => 5, 'response_delay_seconds' => '20')
  end

  it 'does not assign a connected inbox to two agents' do
    assistant.marcosx_ai_inboxes.create!(account: account, inbox: inbox)
    expect {
      post "#{endpoint}/assistants", params: { assistant: { name: 'Conflict', inbox_ids: [inbox.id] } }, headers: admin.create_new_auth_token
    }.not_to change(MarcosxAi::Assistant, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(inbox.reload.marcosx_ai_assistant).to eq(assistant)
  end

  it 'does not disclose a saved API key' do
    get "#{endpoint}/credentials", headers: admin.create_new_auth_token
    expect(response.body).not_to include('test-secret')
    expect(response.parsed_body['credentials'].first['configured']).to be(true)
  end

  it 'keeps the key when saving an empty password field' do
    put "#{endpoint}/credentials/#{credential.id}", params: { credential: { api_key: '', model: 'gpt-6.1-sol' } }, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(credential.reload.api_key).to eq('test-secret')
  end

  it 'restricts connections and activity logs to administrators' do
    get "#{endpoint}/credentials", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
    get "#{endpoint}/logs", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
  end

  it 'protects conversations outside the operator inboxes' do
    assistant.marcosx_ai_inboxes.create!(account: account, inbox: inbox)
    put "#{endpoint}/conversations/#{conversation.display_id}/state", params: { state: { action: 'resume' } }, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
    expect(MarcosxAi::ConversationState.find_by(conversation: conversation)).to be_nil
  end

  it 'pauses a conversation permanently through its own control' do
    assistant.marcosx_ai_inboxes.create!(account: account, inbox: inbox)
    put "#{endpoint}/conversations/#{conversation.display_id}/state", params: { state: { action: 'pause' } }, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['state']).to include('status' => 'paused_by_agent', 'paused_until' => nil, 'assistant_name' => 'Support')
  end

  it 'does not expose private memory in the conversation state' do
    assistant.marcosx_ai_inboxes.create!(account: account, inbox: inbox)
    state = MarcosxAi::ConversationState.for_conversation!(conversation, assistant: assistant)
    state.update!(metadata: { conversation_summary: 'private facts' })
    get "#{endpoint}/conversations/#{conversation.display_id}/state", headers: admin.create_new_auth_token
    expect(response.body).not_to include('private facts')
  end

  it 'starts manual continuation only in the selected conversation' do
    assistant.update!(config: { auto_response_enabled: true, auto_start: false })
    assistant.marcosx_ai_inboxes.create!(account: account, inbox: inbox)
    create(:message, account: account, conversation: conversation, inbox: inbox, message_type: :outgoing)
    expect {
      put "#{endpoint}/conversations/#{conversation.display_id}/state", params: { state: { action: 'reply_now' } }, headers: admin.create_new_auth_token
    }.to have_enqueued_job(MarcosxAi::ResponseJob)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['state']['processing']).to be(true)
  end

  it 'uses the saved reaction setting in the private test area' do
    assistant.update!(config: { allow_reactions: false })
    client = instance_double(MarcosxAi::ProviderClient, usage: {})
    plan = { messages: ['You are welcome'], reaction: nil, reaction_message_id: nil, handoff: false, handoff_reason: nil }
    allow(MarcosxAi::ProviderClient).to receive(:new).and_return(client)
    expect(client).to receive(:chat) do |messages:, schema:|
      expect(messages.first[:content]).to include('use reaction=null e reaction_message_id=null')
      expect(schema).to eq(MarcosxAi::ReplyPlan::SCHEMA)
      plan.to_json
    end
    post "#{endpoint}/assistants/#{assistant.id}/playground", params: { assistant: { message: 'Thank you' } }, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['plan']['reaction']).to be_nil
  end

  it 'lists agents in a conversation with no default inbox agent' do
    get "#{endpoint}/conversations/#{conversation.display_id}/state", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['state']['assistant_id']).to be_nil
    expect(response.parsed_body['assistants'].map { |item| item['id'] }).to include(assistant.id)
  end

  it 'selects an agent for one conversation without changing the inbox default' do
    assistant.marcosx_ai_inboxes.create!(account: account, inbox: inbox)
    another = account.marcosx_ai_assistants.create!(name: 'Individual', config: { auto_response_enabled: true })
    put "#{endpoint}/conversations/#{conversation.display_id}/state",
        params: { state: { action: 'select', assistant_id: another.id } }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['state']).to include('assistant_id' => another.id, 'status' => 'paused_by_agent')
    expect(conversation.reload.marcosx_ai_assistant).to eq(another)
    expect(inbox.reload.marcosx_ai_assistant).to eq(assistant)
    expect(create(:conversation, account: account, inbox: inbox).marcosx_ai_assistant).to eq(assistant)
  end

  it 'enables future messages without scheduling a backlog reply' do
    assistant.update!(config: { auto_response_enabled: true, auto_start: false })
    create(:message, account: account, conversation: conversation, inbox: inbox)
    expect {
      put "#{endpoint}/conversations/#{conversation.display_id}/state",
          params: { state: { action: 'resume', assistant_id: assistant.id } }, headers: admin.create_new_auth_token, as: :json
    }.not_to have_enqueued_job(MarcosxAi::ResponseJob)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['state']['status']).to eq('active')
  end

  it 'enables and pauses one conversation while leaving general support off and another conversation alone' do
    assistant.marcosx_ai_inboxes.create!(account: account, inbox: inbox)
    other = create(:conversation, account: account, inbox: inbox)
    put "#{endpoint}/conversations/#{conversation.display_id}/state",
        params: { state: { action: 'resume' } }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['state']).to include('status' => 'active', 'enabled' => true, 'available' => true, 'manual_activation' => true)
    expect(assistant.reload.auto_response_enabled?).to be(false)
    expect(MarcosxAi::ConversationState.find_by(conversation: other)).to be_nil
    get "#{endpoint}/assistants/#{assistant.id}/coverage", headers: admin.create_new_auth_token
    expect(response.parsed_body).to include('mode' => 'individual', 'total' => 1)
    expect(response.parsed_body['conversations'].first).to include('id' => conversation.display_id, 'contact_name' => conversation.contact.name)

    put "#{endpoint}/conversations/#{conversation.display_id}/state",
        params: { state: { action: 'pause' } }, headers: admin.create_new_auth_token, as: :json
    get "#{endpoint}/assistants/#{assistant.id}/coverage", headers: admin.create_new_auth_token
    expect(response.parsed_body).to include('mode' => 'individual', 'total' => 0, 'conversations' => [])
  end

  it 'requires a configured provider before individually enabling a conversation' do
    credential.update!(enabled: false)
    put "#{endpoint}/conversations/#{conversation.display_id}/state",
        params: { state: { action: 'resume', assistant_id: assistant.id } }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(MarcosxAi::ConversationState.find_by!(conversation: conversation).status).to eq('paused_by_agent')
  end

  it 'keeps automatic coverage compact instead of returning every contact' do
    assistant.update!(config: { auto_response_enabled: true, auto_start: true })
    assistant.marcosx_ai_inboxes.create!(account: account, inbox: inbox)
    MarcosxAi::ConversationState.for_conversation!(conversation, assistant: assistant)
    get "#{endpoint}/assistants/#{assistant.id}/coverage", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('mode' => 'automatic', 'conversations' => [], 'total' => nil)
    expect(response.body).not_to include(conversation.contact.name)
  end

  it 'shows selected conversations when automatic start is disabled and hides resolved conversations' do
    assistant.update!(config: { auto_response_enabled: true, auto_start: false })
    state = MarcosxAi::ConversationState.choose_for_conversation!(conversation, assistant: assistant)
    state.resume!(manual: true)
    get "#{endpoint}/assistants/#{assistant.id}/coverage", headers: admin.create_new_auth_token
    expect(response.parsed_body).to include('mode' => 'individual', 'total' => 1)
    conversation.resolved!
    get "#{endpoint}/assistants/#{assistant.id}/coverage", headers: admin.create_new_auth_token
    expect(response.parsed_body['total']).to eq(0)
  end

  it 'scopes coverage and activity to the selected account and administrator' do
    other = create(:account).marcosx_ai_assistants.create!(name: 'Other')
    get "#{endpoint}/assistants/#{other.id}/coverage", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:not_found)
    get "#{endpoint}/assistants/#{assistant.id}/coverage", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
    get "#{endpoint}/logs", params: { assistant_id: other.id }, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:not_found)
  end

  it 'filters recent activity by agent before applying the result limit' do
    other = account.marcosx_ai_assistants.create!(name: 'Other')
    first = MarcosxAi::Log.create!(account: account, assistant: assistant, conversation: conversation, event: 'analysis_ready')
    MarcosxAi::Log.create!(account: account, assistant: other, event: 'response_generated')
    get "#{endpoint}/logs", params: { assistant_id: assistant.id }, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['logs'].map { |log| log['id'] }).to eq([first.id])
    expect(response.parsed_body['logs'].first['assistant_id']).to eq(assistant.id)
  end

  it 'rejects an agent from another account before changing the conversation' do
    other = create(:account).marcosx_ai_assistants.create!(name: 'Other')
    post "#{endpoint}/conversations/#{conversation.display_id}/analysis",
         params: { analysis: { assistant_id: other.id } }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
    expect(MarcosxAi::ConversationState.find_by(conversation: conversation)).to be_nil
  end

  it 'rejects invalid state actions without assigning an agent' do
    put "#{endpoint}/conversations/#{conversation.display_id}/state",
        params: { state: { action: 'bad', assistant_id: assistant.id } }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(MarcosxAi::ConversationState.find_by(conversation: conversation)).to be_nil
  end

  it 'protects history analysis outside the operator inboxes' do
    post "#{endpoint}/conversations/#{conversation.display_id}/analysis",
         params: { analysis: { assistant_id: assistant.id } }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(MarcosxAi::ConversationState.find_by(conversation: conversation)).to be_nil
  end

  it 'saves a timezone for the agent without changing its other settings' do
    put "#{endpoint}/assistants/#{assistant.id}",
        params: { assistant: { config: { timezone: 'America/Araguaina' } } }, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(assistant.reload.resolved_config).to include('timezone' => 'America/Araguaina', 'auto_response_enabled' => false)
  end

  it 'rejects an unknown timezone without changing the saved agent' do
    put "#{endpoint}/assistants/#{assistant.id}",
        params: { assistant: { config: { timezone: 'Unknown/Place' } } }, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:unprocessable_entity)
    expect(assistant.reload.resolved_config[:timezone]).to be_nil
  end

  it 'keeps the same manually enabled agent active while starting a limited analysis' do
    create(:message, account: account, inbox: inbox, conversation: conversation)
    state = MarcosxAi::ConversationState.choose_for_conversation!(conversation, assistant: assistant)
    state.resume!(manual: true)
    post "#{endpoint}/conversations/#{conversation.display_id}/analysis",
         params: { analysis: { assistant_id: assistant.id, messages_limit: 1 } }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:accepted)
    expect(state.reload.public_data).to include(status: 'active', manual_activation: true, enabled: true)
    expect(response.parsed_body['analysis']).to include('messages_count' => 1, 'messages_limit' => 1)
    get "#{endpoint}/conversations/#{conversation.display_id}/analysis", headers: admin.create_new_auth_token
    expect(response.parsed_body['context']).to include('total_messages_count' => 1, 'messages_limit' => 1)
  end

  it 'rejects an invalid context limit before assigning an agent' do
    post "#{endpoint}/conversations/#{conversation.display_id}/analysis",
         params: { analysis: { assistant_id: assistant.id, messages_limit: -1 } }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(MarcosxAi::ConversationState.find_by(conversation: conversation)).to be_nil
  end

  it 'shows the available public message count before selecting an agent' do
    create(:message, account: account, inbox: inbox, conversation: conversation)
    create(:message, account: account, inbox: inbox, conversation: conversation, private: true)
    get "#{endpoint}/conversations/#{conversation.display_id}/analysis", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('analysis' => { 'status' => 'idle' },
                                          'context' => { 'total_messages_count' => 1, 'messages_limit' => nil })
  end

  it 'tests attachments without creating messages or keeping temporary files' do
    client = instance_double(MarcosxAi::ProviderClient, usage: {})
    plan = { messages: ['That is an image'], reaction: nil, reaction_message_id: nil, handoff: false, handoff_reason: nil }
    allow(MarcosxAi::ProviderClient).to receive(:new).and_return(client)
    allow(client).to receive(:chat).and_return(plan.to_json)
    allow_any_instance_of(MarcosxAi::MediaContext).to receive(:describe).and_return('A red box')
    baseline = ActiveStorage::Blob.count
    expect {
      post "#{endpoint}/assistants/#{assistant.id}/playground", params: {
        assistant: { message: 'What is this?', history: [{ role: 'user', content: 'Hi' }, { role: 'assistant', content: 'Hello' }] },
        files: [fixture_file_upload('spec/assets/avatar.png', 'image/png')]
      }, headers: admin.create_new_auth_token
    }.not_to change(Message, :count)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['user_context']).to include('A red box')
    expect(ActiveStorage::Blob.count).to eq(baseline)
  end
  it 'generates a composer draft with the selected agent and leaves the conversation unchanged' do
    assistant.marcosx_ai_inboxes.create!(account: account, inbox: inbox)
    service = instance_double(MarcosxAi::ComposerDraftService, perform: { content: 'Review me' })
    allow(MarcosxAi::ComposerDraftService).to receive(:new).with(conversation: conversation, action: 'reply_suggestion',
                                                               content: nil, instruction: nil).and_return(service)
    post "#{endpoint}/conversations/#{conversation.display_id}/draft", params: { draft: { action: 'reply_suggestion' } }, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['content']).to eq('Review me')
    expect(conversation.messages.outgoing).to be_empty
    expect(conversation.reload.marcosx_ai_conversation_state).to be_nil
  end

  it 'protects composer drafts outside the operator inboxes' do
    expect(MarcosxAi::ComposerDraftService).not_to receive(:new)
    post "#{endpoint}/conversations/#{conversation.display_id}/draft", params: { draft: { action: 'reply_suggestion' } }, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
  end

end

