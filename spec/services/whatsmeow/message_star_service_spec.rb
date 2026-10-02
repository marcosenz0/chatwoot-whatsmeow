require 'rails_helper'

RSpec.describe Whatsmeow::MessageStarService do
  let(:account) { create(:account) }
  let(:inbox) { create(:channel_whatsmeow, account: account).inbox }
  let(:contact_inbox) { create(:contact_inbox, inbox: inbox, source_id: '120363000000001@g.us') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact_inbox.contact, contact_inbox: contact_inbox) }
  let(:message) { create(:message, account: account, inbox: inbox, conversation: conversation, source_id: 'favorite-source') }
  let(:event) { { chat: contact_inbox.source_id, message_id: 'favorite-source', starred: true, timestamp: Time.current.to_i } }
  let(:client) { instance_double(Whatsmeow::SessionClient, star_message: { 'starred' => true }) }

  it 'attaches a favorite imported before its original message' do
    described_class.apply_incoming(inbox: inbox, params: event)
    expect(WhatsmeowMessageStar.last.message_id).to be_nil
    described_class.attach(message)
    expect(WhatsmeowMessageStar.last.message).to eq(message)
    expect(message.reload.content_attributes['whatsmeow_starred']).to be(true)
  end

  it 'keeps the newer change when an older full sync arrives afterwards' do
    message
    described_class.apply_incoming(inbox: inbox, params: event.merge(starred: false))
    described_class.apply_incoming(inbox: inbox, params: event.merge(timestamp: event[:timestamp] - 60))
    expect(WhatsmeowMessageStar.count).to eq(1)
    expect(message.reload.content_attributes['whatsmeow_starred']).to be(false)
  end

  it 'updates WhatsApp before storing the local favorite' do
    allow(Whatsmeow::SessionClient).to receive(:new).with(inbox: inbox).and_return(client)
    message.update!(content_attributes: { participant_jid: '556392977347@s.whatsapp.net' })
    described_class.new(inbox: inbox, chat_jid: contact_inbox.source_id, source_id: message.source_id).perform(message: message, starred: true)
    expect(client).to have_received(:star_message).with(hash_including(chat: contact_inbox.source_id, starred: true, from_me: false))
    expect(message.reload.content_attributes['whatsmeow_starred']).to be(true)
  end

  it 'does not save a favorite when WhatsApp rejects the operation' do
    allow(Whatsmeow::SessionClient).to receive(:new).and_return(client)
    allow(client).to receive(:star_message).and_raise(Whatsmeow::SessionClient::Error, 'Disconnected')
    service = described_class.new(inbox: inbox, chat_jid: contact_inbox.source_id, source_id: message.source_id)
    expect { service.perform(message: message, starred: true) }.to raise_error(Whatsmeow::SessionClient::Error)
    expect(WhatsmeowMessageStar.count).to eq(0)
  end

  it 'rejects internal notes and non-boolean input' do
    service = described_class.new(inbox: inbox, chat_jid: contact_inbox.source_id, source_id: message.source_id)
    expect { service.perform(message: message, starred: 'true') }.to raise_error(ArgumentError)
    message.update!(private: true)
    expect { service.perform(message: message, starred: true) }.to raise_error(ArgumentError)
  end
end
