require 'rails_helper'

RSpec.describe 'Whatsmeow groups API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:channel_whatsmeow, account: account).inbox }
  let(:client) { instance_double(Whatsmeow::SessionClient) }
  let(:endpoint) { "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/whatsmeow_group" }
  let(:group) { { 'group_jid' => '120363000000001@g.us', 'group_name' => 'Test group', 'count' => 3 } }

  before do
    create(:inbox_member, inbox: inbox, user: agent)
    allow(Whatsmeow::SessionClient).to receive(:new).with(inbox: inbox).and_return(client)
  end

  it 'creates the WhatsApp group and its Chatwoot conversation' do
    allow(client).to receive(:create_group).and_return(group)
    post endpoint, params: { name: 'Test group', allow_member_send: false, participants: ['556392977347@s.whatsapp.net'] },
                   headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:created)
    expect(client).to have_received(:create_group).with(hash_including('allow_member_send' => false))
    expect(account.conversations.find_by!(display_id: response.parsed_body['conversation_id']).contact_inbox.source_id).to eq(group['group_jid'])
  end

  it 'keeps the operation separate from the Rails action parameter' do
    allow(client).to receive(:group_action).and_return('invite_link' => 'https://chat.whatsapp.com/example')
    post "#{endpoint}/action", params: { group_jid: group['group_jid'], operation: 'invite' }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(client).to have_received(:group_action).with(hash_including('operation' => 'invite'))
  end

  it 'returns service failures without creating a conversation' do
    allow(client).to receive(:create_group).and_raise(Whatsmeow::SessionClient::Error, 'WhatsApp session is not connected')
    post endpoint, params: { name: 'Test group' }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(account.conversations).to be_empty
  end

  it 'denies access to an inbox outside the account' do
    expect(client).not_to receive(:group_action)
    other = create(:channel_whatsmeow).inbox
    get "/api/v1/accounts/#{account.id}/inboxes/#{other.id}/whatsmeow_group", params: { group_jid: group['group_jid'] },
                                                                                       headers: agent.create_new_auth_token
    expect(response).to have_http_status(:not_found)
  end
end
