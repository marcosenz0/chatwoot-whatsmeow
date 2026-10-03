require 'rails_helper'

RSpec.describe 'Whatsmeow deleted messages API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:channel_whatsmeow, account: account).inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let!(:message) do
    create(:message, account: account, inbox: inbox, conversation: conversation, content: 'Preserved content',
                     content_attributes: { deleted: true, whatsmeow_deleted: true, participant_name: 'Group sender' })
  end
  let(:endpoint) { "/api/v1/accounts/#{account.id}/whatsmeow_deleted_messages" }

  before { create(:inbox_member, inbox: inbox, user: agent) }

  it 'returns retained content and the original conversation anchor' do
    get endpoint, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['payload'].first).to include('conversation_id' => conversation.display_id, 'sender_name' => 'Group sender')
    expect(response.parsed_body['payload'].first['message']).to include('id' => message.id, 'content' => 'Preserved content')
  end

  it 'excludes private notes and local deletions that were not revoked on WhatsApp' do
    message.update!(private: true)
    create(:message, account: account, inbox: inbox, conversation: conversation, content_attributes: { deleted: true, deleted_by: agent.id })
    get endpoint, headers: agent.create_new_auth_token
    expect(response.parsed_body['payload']).to be_empty
  end

  it 'excludes messages from another account or an inaccessible inbox' do
    other_inbox = create(:channel_whatsmeow, account: account).inbox
    other_conversation = create(:conversation, account: account, inbox: other_inbox)
    create(:message, account: account, inbox: other_inbox, conversation: other_conversation, content_attributes: { whatsmeow_deleted: true })
    create(:message, content_attributes: { whatsmeow_deleted: true })
    get endpoint, headers: agent.create_new_auth_token
    expect(response.parsed_body['payload'].pluck('id')).to eq([message.id])
  end

  it 'searches content and group senders, with inbox and conversation filters' do
    get endpoint, params: { q: 'Group sender', inbox_id: inbox.id, conversation_id: conversation.display_id }, headers: agent.create_new_auth_token
    expect(response.parsed_body['payload'].pluck('id')).to eq([message.id])
    get endpoint, params: { q: 'Preserved', conversation_id: conversation.display_id + 1 }, headers: agent.create_new_auth_token
    expect(response.parsed_body['payload']).to be_empty
  end

  it 'paginates identical timestamps without duplicating or skipping messages' do
    create_list(
      :message, 50,
      account: account, inbox: inbox, conversation: conversation,
      created_at: message.created_at, content_attributes: { whatsmeow_deleted: true }
    )
    get endpoint, headers: agent.create_new_auth_token
    first_page = response.parsed_body
    expect(first_page['payload'].length).to eq(50)
    get endpoint, params: { before: first_page['next_cursor'] }, headers: agent.create_new_auth_token
    expect(response.parsed_body['payload'].pluck('id')).to eq([message.id])
    expect(response.parsed_body['next_cursor']).to be_nil
  end
end
