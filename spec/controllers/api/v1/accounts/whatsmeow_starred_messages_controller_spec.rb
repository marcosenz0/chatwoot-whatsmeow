require 'rails_helper'

RSpec.describe 'Whatsmeow starred messages API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:channel_whatsmeow, account: account).inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:message) { create(:message, account: account, inbox: inbox, conversation: conversation, source_id: 'favorite') }
  let(:endpoint) { "/api/v1/accounts/#{account.id}/whatsmeow_starred_messages" }
  let!(:star) { WhatsmeowMessageStar.create!(inbox: inbox, message: message, chat_jid: '120363000000001@g.us', source_id: message.source_id, occurred_at: Time.current) }

  before { create(:inbox_member, inbox: inbox, user: agent) }

  it 'returns a formatted original message with its conversation anchor' do
    get endpoint, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['payload'].first).to include('conversation_id' => conversation.display_id, 'inbox_id' => inbox.id)
    expect(response.parsed_body['payload'].first['message']['id']).to eq(message.id)
  end

  it 'excludes favorites from inboxes the agent cannot access' do
    other_inbox = create(:channel_whatsmeow, account: account).inbox
    other_conversation = create(:conversation, account: account, inbox: other_inbox)
    other_message = create(:message, account: account, inbox: other_inbox, conversation: other_conversation)
    WhatsmeowMessageStar.create!(inbox: other_inbox, message: other_message, chat_jid: '120363000000002@g.us',
                                source_id: 'other-favorite', occurred_at: Time.current)
    get endpoint, headers: agent.create_new_auth_token
    expect(response.parsed_body['payload'].pluck('id')).to eq([star.id])
  end

  it 'does not expose private messages' do
    message.update!(private: true)
    get endpoint, headers: agent.create_new_auth_token
    expect(response.parsed_body['payload']).to be_empty
  end

  it 'searches message contents and limits favorites to one conversation' do
    message.update!(content: 'Remember the deployment')
    get endpoint, params: { q: 'deployment', conversation_id: conversation.display_id }, headers: agent.create_new_auth_token
    expect(response.parsed_body['payload'].pluck('id')).to eq([star.id])
  end

  it 'keeps an imported favorite pending when its message is not available yet' do
    star.update!(message: nil)
    get endpoint, headers: agent.create_new_auth_token
    expect(response.parsed_body).to include('payload' => [], 'pending_count' => 1)
  end
end
