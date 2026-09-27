require 'rails_helper'

RSpec.describe 'Whatsmeow Pix messages API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:channel) { create(:channel_whatsmeow, account: account) }
  let(:inbox) { channel.inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:endpoint) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages/pix" }

  before do
    create(:inbox_member, inbox: inbox, user: agent)
  end

  it 'creates an outgoing Pix message from the inbox configuration' do
    channel.update!(pix_key_type: 'EMAIL', pix_key: 'payments@example.com', pix_merchant_name: 'Example Store')

    post endpoint, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    message = conversation.messages.last
    expect(message).to have_attributes(content: 'Example Store', message_type: 'outgoing', private: false)
    expect(message.content_attributes['whatsmeow_pix']).to eq(
      'key_type' => 'EMAIL',
      'key' => 'payments@example.com',
      'merchant_name' => 'Example Store'
    )
  end

  it 'accepts an explicit key without changing the inbox configuration' do
    post endpoint,
         params: { key_type: 'CPF', key: '529.982.247-25', merchant_name: 'One-off recipient' },
         headers: agent.create_new_auth_token,
         as: :json

    expect(response).to have_http_status(:ok)
    expect(conversation.messages.last.content_attributes.dig('whatsmeow_pix', 'key')).to eq('52998224725')
    expect(channel.reload.pix_configured?).to be(false)
  end

  it 'accepts an AgentBot API token for an automated Pix send' do
    bot = create(:agent_bot, account: account)
    create(:agent_bot_inbox, inbox: inbox, agent_bot: bot)

    post endpoint,
         params: { key_type: 'EMAIL', key: 'payments@example.com', merchant_name: 'Example Store' },
         headers: { api_access_token: bot.access_token.token },
         as: :json

    expect(response).to have_http_status(:ok)
    expect(conversation.messages.last.sender).to eq(bot)
  end

  it 'rejects a bot that is only linked to another inbox in the account' do
    bot = create(:agent_bot, account: account)
    other_channel = create(:channel_whatsmeow, account: account)
    create(:agent_bot_inbox, inbox: other_channel.inbox, agent_bot: bot)

    post endpoint,
         params: { key_type: 'EMAIL', key: 'payments@example.com', merchant_name: 'Example Store' },
         headers: { api_access_token: bot.access_token.token },
         as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(conversation.messages).to be_empty
  end

  it 'returns a structured error when no key is configured or provided' do
    post endpoint, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.dig('error', 'code')).to eq('pix_not_configured')
  end

  it 'does not send the saved key when explicit fields are blank' do
    channel.update!(pix_key_type: 'EMAIL', pix_key: 'payments@example.com', pix_merchant_name: 'Example Store')

    post endpoint,
         params: { key_type: '', key: '', merchant_name: '' },
         headers: agent.create_new_auth_token,
         as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.dig('error', 'code')).to eq('invalid_pix_payload')
    expect(conversation.messages).to be_empty
  end

  it 'does not fall back to the saved key for an invalid automation payload' do
    channel.update!(pix_key_type: 'EMAIL', pix_key: 'payments@example.com', pix_merchant_name: 'Example Store')

    post endpoint,
         params: { key: [] },
         headers: agent.create_new_auth_token,
         as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.dig('error', 'code')).to eq('invalid_pix_payload')
    expect(conversation.messages).to be_empty
  end

  it 'rejects the endpoint for another channel type' do
    other_conversation = create(:conversation, account: account)
    create(:inbox_member, inbox: other_conversation.inbox, user: agent)

    post "/api/v1/accounts/#{account.id}/conversations/#{other_conversation.display_id}/messages/pix",
         params: { key_type: 'EMAIL', key: 'payments@example.com', merchant_name: 'Example Store' },
         headers: agent.create_new_auth_token,
         as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.dig('error', 'code')).to eq('unsupported_channel')
  end
end
