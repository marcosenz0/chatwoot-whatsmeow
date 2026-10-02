require 'rails_helper'

RSpec.describe 'Whatsmeow conversation actions API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:channel_whatsmeow, account: account).inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: agent, agent_last_seen_at: 3.days.ago) }
  let(:endpoint) { "/api/v1/accounts/#{account.id}/whatsmeow_conversations" }

  before { create(:inbox_member, inbox: inbox, user: agent) }

  it 'marks accessible conversations as read for their assigned agent' do
    create(:message, account: account, inbox: inbox, conversation: conversation)
    post "#{endpoint}/read_all", params: { inbox_id: inbox.id }, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(conversation.reload.agent_last_seen_at).to be > 1.minute.ago
    expect(conversation.assignee_last_seen_at).to eq(conversation.agent_last_seen_at)
  end

  it 'leaves an inaccessible inbox unread' do
    other_inbox = create(:channel_whatsmeow, account: account).inbox
    other_conversation = create(:conversation, account: account, inbox: other_inbox, agent_last_seen_at: 3.days.ago)
    seen_at = other_conversation.agent_last_seen_at
    post "#{endpoint}/read_all", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(other_conversation.reload.agent_last_seen_at).to eq(seen_at)
  end

  it 'exports public messages in chronological order and excludes internal notes' do
    create(:message, account: account, inbox: inbox, conversation: conversation, content: 'Later message')
    create(:message, account: account, inbox: inbox, conversation: conversation, content: 'Earlier message', created_at: 1.day.ago)
    create(:message, account: account, inbox: inbox, conversation: conversation, content: 'Private note', private: true)
    get "#{endpoint}/#{conversation.display_id}/export", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Earlier message', 'Later message')
    expect(response.body.index('Earlier message')).to be < response.body.index('Later message')
    expect(response.body).not_to include('Private note')
  end
end
