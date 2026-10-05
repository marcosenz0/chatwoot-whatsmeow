require 'rails_helper'

RSpec.describe 'Telegram personal account callbacks', type: :request do
  let(:channel) { create(:channel_telegram_personal) }
  let(:inbox) { channel.inbox }
  let(:endpoint) { "/webhooks/telegram_personal/#{inbox.account_id}/#{inbox.id}" }
  let(:payload) { { event: 'message', source_id: '42:100', chat_id: '42', chat_name: 'Test', content: 'Hello', date: Time.current.to_i } }

  it 'fails closed when the server shared secret is missing' do
    with_modified_env TELEGRAM_PERSONAL_SHARED_SECRET: nil do
      post endpoint, params: { payload: payload }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  it 'rejects an invalid callback token' do
    with_modified_env TELEGRAM_PERSONAL_SHARED_SECRET: 's' * 32 do
      post endpoint, params: { payload: payload }, headers: { Authorization: 'Bearer invalid' }, as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(inbox.messages).to be_empty
    end
  end

  it 'imports retries once with the valid internal token' do
    with_modified_env TELEGRAM_PERSONAL_SHARED_SECRET: 's' * 32 do
      2.times { post endpoint, params: { payload: payload }, headers: { Authorization: "Bearer #{'s' * 32}" }, as: :json }
      expect(response).to have_http_status(:ok)
      expect(inbox.messages.count).to eq(1)
    end
  end
end
