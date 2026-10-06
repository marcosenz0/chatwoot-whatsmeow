require 'rails_helper'

RSpec.describe TelegramPersonal::SendOnTelegramPersonalService do
  let(:channel) { create(:channel_telegram_personal) }
  let(:inbox) { channel.inbox }
  let(:contact_inbox) { create(:contact_inbox, inbox: inbox, source_id: '42') }
  let(:conversation) { create(:conversation, inbox: inbox, account: inbox.account, contact_inbox: contact_inbox, contact: contact_inbox.contact) }
  let(:message) { create(:message, message_type: :outgoing, inbox: inbox, account: inbox.account, conversation: conversation, content: 'Reply') }
  let(:client) { instance_double(TelegramPersonal::SessionClient) }

  before do
    allow(TelegramPersonal::SessionClient).to receive(:new).with(inbox: inbox).and_return(client)
  end

  it 'routes the message through the personal account and stores Telegram ids' do
    expect(client).to receive(:send_message).with(hash_including(request_id: message.id.to_s, chat_id: '42', content: 'Reply'))
                                            .and_return('source_id' => '42:120', 'message_ids' => [120])
    described_class.new(message: message).perform
    expect(message.reload.source_id).to eq('42:120')
    expect(message.external_source_ids['telegram_personal']).to eq([120])
  end

  it 'does not send phone echoes or private notes' do
    message.update!(source_id: '42:120')
    expect(client).not_to receive(:send_message)
    described_class.new(message: message).perform
    message.update!(source_id: nil, private: true)
    described_class.new(message: message).perform
  end

  it 'reports Telegram rejection as failed without storing a secret or inventing a source id' do
    allow(client).to receive(:send_message).and_raise(TelegramPersonal::SessionClient::Error, 'not_connected')
    described_class.new(message: message).perform
    expect(message.reload).to be_failed
    expect(message.source_id).to be_nil
    expect(message.external_error).to eq('not_connected')
  end
end
