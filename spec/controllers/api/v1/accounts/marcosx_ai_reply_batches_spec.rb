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

  it 'recovers only the signed-in operator active batches across agents' do
    post endpoint, params: attributes, headers: admin.create_new_auth_token, as: :json
    own_id = response.parsed_body['batch']['id']
    other_admin = create(:user, account: account, role: :administrator)
    assistant.reply_batches.create!(account: account, user: other_admin, mode: 'direct', request_id: 'other')
    get "/api/v1/accounts/#{account.id}/marcosx_ai/reply_batches", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body['batches'].pluck('id')).to eq([own_id])
    expect(response.parsed_body['batches'].first['assistant_id']).to eq(assistant.id)
  end

  it 'removes a reserved turn from pending immediately and reports provider delivery failures separately' do
    post endpoint, params: attributes, headers: admin.create_new_auth_token, as: :json
    item = assistant.reply_batches.first.items.first
    get endpoint, headers: admin.create_new_auth_token
    expect(response.parsed_body['conversations']).to be_empty
    outgoing = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, sender: assistant,
                                additional_attributes: { trigger_message_id: message.id })
    item.update!(status: 'sent')
    expect(item.delivery_status).to eq('delivery_pending')
    outgoing.update!(status: :failed)
    expect(item.delivery_status).to eq('delivery_failed')
    outgoing.update!(status: :delivered, source_id: 'provider-confirmed')
    expect(item.delivery_status).to eq('delivered')
  end
end
