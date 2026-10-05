require 'rails_helper'

RSpec.describe 'Telegram personal account API', type: :request do
  let(:channel) { create(:channel_telegram_personal) }
  let(:inbox) { channel.inbox }
  let(:admin) { create(:user, account: inbox.account, role: :administrator) }
  let(:agent) { create(:user, account: inbox.account, role: :agent) }
  let(:endpoint) { "/api/v1/accounts/#{inbox.account_id}/inboxes/#{inbox.id}/telegram_personal" }
  let(:client) { instance_double(TelegramPersonal::SessionClient, status: { 'status' => 'connected', 'telegram_user_id' => '42' }) }

  before do
    allow(TelegramPersonal::SessionClient).to receive(:new).with(inbox: inbox).and_return(client)
  end

  it 'allows the administrator to inspect pairing and prevents caching the QR' do
    get endpoint, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.headers['Cache-Control']).to include('no-store')
    expect(channel.reload.status).to eq('connected')
  end

  it 'does not give an assigned agent access to QR codes or two-step password submission' do
    create(:inbox_member, inbox: inbox, user: agent)
    get endpoint, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
    post "#{endpoint}/password", params: { password: 'test' }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'does not allow an administrator from another account to pair this inbox' do
    other_admin = create(:user, account: create(:account), role: :administrator)
    post endpoint, headers: other_admin.create_new_auth_token, as: :json
    expect(response).not_to have_http_status(:ok)
    expect(client).not_to receive(:connect)
  end

  it 'accepts the personal channel through standard inbox creation' do
    post "/api/v1/accounts/#{inbox.account_id}/inboxes", params: {
      name: 'Telegram Test', channel: { type: 'telegram_personal', phone_number: '+15551234567' }
    }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['channel_type']).to eq('Channel::TelegramPersonal')
    expect(response.parsed_body).not_to have_key('api_hash')
  end
end
