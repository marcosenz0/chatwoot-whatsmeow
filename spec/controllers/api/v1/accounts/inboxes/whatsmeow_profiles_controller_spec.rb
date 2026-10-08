require 'rails_helper'

RSpec.describe 'WhatsApp connected profile API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:channel_whatsmeow, account: account).inbox }
  let(:client) { instance_double(Whatsmeow::SessionClient) }
  let(:endpoint) { "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/whatsmeow_profile" }

  before do
    create(:inbox_member, inbox: inbox, user: agent)
    allow(Whatsmeow::SessionClient).to receive(:new).with(inbox: inbox).and_return(client)
  end

  it 'loads the current WhatsApp profile rather than the inbox avatar' do
    allow(client).to receive(:own_profile).and_return('name' => 'Owner', 'about' => 'Available', 'photo_url' => 'https://example.com/full.jpg')
    get endpoint, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['name']).to eq('Owner')
    expect(response.parsed_body['photo_url']).to eq('https://example.com/full.jpg')
  end

  it 'limits updates to allowed profile fields and ignores external targets' do
    allow(client).to receive(:update_profile).and_return('success' => true)
    patch endpoint, headers: admin.create_new_auth_token, as: :json,
                    params: { name: 'Owner', jid: 'other@s.whatsapp.net', account_id: account.id, business: {
                      email: 'owner@example.com', websites: ['https://example.com'], categories: ['unsupported'],
                      hours: { timezone: 'America/Sao_Paulo', days: [{ day: 'mon', mode: 'open_24h', open: 0, close: 0 }] }
                    } }
    expect(response).to have_http_status(:ok)
    expect(client).to have_received(:update_profile).with({
      'name' => 'Owner', 'business' => { 'email' => 'owner@example.com', 'websites' => ['https://example.com'],
                                       'hours' => { 'timezone' => 'America/Sao_Paulo', 'days' => [{ 'day' => 'mon', 'mode' => 'open_24h', 'open' => 0, 'close' => 0 }] } }
    })
  end

  it 'lets assigned agents view the own full photo but not edit the WhatsApp profile' do
    allow(client).to receive(:own_profile_photo).and_return('photo_url' => 'https://example.com/full.jpg')
    get "#{endpoint}/photo", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(client).not_to receive(:update_profile)
    patch endpoint, params: { name: 'Changed' }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body['error']).to eq('You are not authorized to do this action')
  end

  it 'uploads the cropped JPEG to the connected WhatsApp account' do
    allow(client).to receive(:update_profile_photo).with('jpeg-bytes').and_return('photo_url' => 'https://example.com/new.jpg')
    put "#{endpoint}/photo", params: { photo: 'jpeg-bytes' }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['photo_url']).to eq('https://example.com/new.jpg')
  end

  it 'removes only the connected WhatsApp profile photo' do
    allow(client).to receive(:remove_profile_photo).and_return('photo_url' => '', 'photo_status' => 'none')
    delete "#{endpoint}/photo", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['photo_status']).to eq('none')
  end

  it 'rejects another account inbox' do
    other = create(:channel_whatsmeow).inbox
    get "/api/v1/accounts/#{account.id}/inboxes/#{other.id}/whatsmeow_profile", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:not_found)
  end

  it 'reports bridge failures instead of claiming a successful edit' do
    allow(client).to receive(:update_profile).and_raise(Whatsmeow::SessionClient::Error, 'Disconnected')
    patch endpoint, params: { about: 'New about' }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
