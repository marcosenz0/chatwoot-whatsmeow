require 'rails_helper'

RSpec.describe 'Instagram previews API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:url) { 'https://www.instagram.com/example.user/' }
  let(:message) { create(:message, conversation: conversation, account: account, inbox: inbox, content: url) }
  let(:endpoint) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages/#{message.id}/instagram_preview" }

  before do
    create(:inbox_member, inbox: inbox, user: agent)
  end

  it 'requires authentication' do
    get endpoint, params: { url: url }
    expect(response).to have_http_status(:unauthorized)
  end

  it 'fetches only a URL already belonging to the authorized message' do
    service = instance_double(Instagram::PreviewService, perform: { url: url, kind: 'profile', status: 'limited' })
    allow(Instagram::PreviewService).to receive(:new).with(url: url).and_return(service)
    get endpoint, params: { url: url }, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('url' => url, 'kind' => 'profile')
  end

  it 'rejects arbitrary URL fetching' do
    expect(Instagram::PreviewService).not_to receive(:new)
    get endpoint, params: { url: 'https://www.instagram.com/another.user/' }, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'does not expose messages from another conversation' do
    other_conversation = create(:conversation, account: account, inbox: inbox)
    other_message = create(:message, conversation: other_conversation, account: account, inbox: inbox, content: url)
    get endpoint.sub("/messages/#{message.id}/", "/messages/#{other_message.id}/"),
        params: { url: url }, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:not_found)
  end
end
