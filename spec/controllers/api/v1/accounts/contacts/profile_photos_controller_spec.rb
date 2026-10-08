require 'rails_helper'

RSpec.describe 'Contact full profile photo API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:contact) { create(:contact, account: account) }
  let(:inbox) { create(:channel_whatsmeow, account: account).inbox }
  let(:client) { instance_double(Whatsmeow::SessionClient) }
  let(:endpoint) { "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/profile_photo" }

  before do
    create(:inbox_member, inbox: inbox, user: agent)
    create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5511999991111@s.whatsapp.net')
    allow(Whatsmeow::SessionClient).to receive(:new).with(inbox: inbox).and_return(client)
  end

  it 'requests the full image using the trusted contact inbox identity' do
    allow(client).to receive(:full_profile_photo).with('5511999991111@s.whatsapp.net').and_return('photo_url' => 'https://example.com/full.jpg')
    get endpoint, params: { inbox_id: inbox.id, jid: 'spoofed@s.whatsapp.net' }, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['photo_url']).to eq('https://example.com/full.jpg')
  end

  it 'respects hidden photos without exposing an old saved avatar' do
    allow(client).to receive(:full_profile_photo).and_return('photo_url' => '', 'photo_status' => 'hidden')
    get endpoint, params: { inbox_id: inbox.id }, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['photo_url']).to eq('')
    expect(response.parsed_body['photo_status']).to eq('hidden')
  end

  it 'denies a contact outside the account' do
    other = create(:contact)
    get "/api/v1/accounts/#{account.id}/contacts/#{other.id}/profile_photo", params: { inbox_id: inbox.id }, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:not_found)
  end

  it 'denies an inbox the agent cannot access' do
    other = create(:channel_whatsmeow, account: account).inbox
    get endpoint, params: { inbox_id: other.id }, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:forbidden)
  end

  it 'does not use a contact identity belonging to another inbox' do
    other = create(:channel_whatsmeow, account: account).inbox
    create(:inbox_member, inbox: other, user: agent)
    get endpoint, params: { inbox_id: other.id }, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:not_found)
  end

  it 'uses the original stored avatar for other channels' do
    contact.avatar.attach(io: File.open(Rails.root.join('spec/assets/avatar.png')), filename: 'avatar.png', content_type: 'image/png')
    get endpoint, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['photo_url']).to include('/rails/active_storage/blobs/')
    expect(response.parsed_body['photo_url']).not_to include('/representations/')
  end
end
