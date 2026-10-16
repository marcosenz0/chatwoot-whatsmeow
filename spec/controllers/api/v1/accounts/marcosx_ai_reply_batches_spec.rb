require 'rails_helper'

RSpec.describe 'MarcoXIA reply batch API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:assistant) { account.marcosx_ai_assistants.create!(name: 'Support') }
  let(:inbox) { create(:channel_whatsmeow, account: account).inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let!(:message) { create(:message, account: account, inbox: inbox, conversation: conversation, content: 'A question') }
  let(:endpoint) { "/api/v1/accounts/#{account.id}/marcosx_ai/assistants/#{assistant.id}/reply_batches" }
  let(:attributes) { { mode: 'review', request_id: 'request-1', selections: [{ id: conversation.display_id, trigger_message_id: message.id }] } }
  before do
    assistant.marcosx_ai_inboxes.create!(account: account, inbox: inbox)
    account.marcosx_ai_credentials.create!(provider: 'openai', api_key: 'test', enabled: true)
  end

  it 'lists eligible pending contacts and previews history without marking it read or creating state' do
    get endpoint, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body['total']).to eq(1)
    expect(response.parsed_body['conversations'].first['id']).to eq(conversation.display_id)
    expect {
      get "#{endpoint}/preview", params: { conversation_id: conversation.display_id }, headers: admin.create_new_auth_token
    }.not_to change(MarcosxAi::ConversationState, :count)
    expect(response.parsed_body['messages'].last['content']).to eq('A question')
  end

  it 'persists an idempotent selection, discards a review and queues only remaining reviews' do
    post endpoint, params: attributes, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:accepted), response.body
    id = response.parsed_body['batch']['id']
    post endpoint, params: attributes, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['batch']['id']).to eq(id)
    expect(assistant.reply_batches.count).to eq(1)
    item = assistant.reply_batches.first.items.first
    item.update!(status: 'ready', plan: { messages: ['Preview'] })
    item.reply_batch.update!(status: 'ready')
    patch "#{endpoint}/#{id}", params: { operation: 'discard', item_id: item.id }, headers: admin.create_new_auth_token, as: :json
    expect(item.reload.status).to eq('discarded')
    expect(conversation.messages.outgoing.where(private: false)).to be_empty
  end

  it 'rejects malformed selections and restricts batches to the operator and account' do
    post endpoint, params: attributes.merge(selections: [{ id: '1', trigger_message_id: message.id }]), headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    other = create(:user, account: account, role: :agent)
    post endpoint, params: attributes, headers: other.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized).or have_http_status(:forbidden)
    expect(assistant.reply_batches).to be_empty
  end
end
