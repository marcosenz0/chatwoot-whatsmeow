require 'rails_helper'

RSpec.describe Whatsmeow::ChatReadService do
  let(:account) { create(:account) }
  let(:inbox) { create(:channel_whatsmeow, account: account).inbox }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, inbox: inbox, contact: contact, source_id: '556391189840@s.whatsapp.net') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:first_message_at) { 2.hours.ago.change(usec: 0) }
  let(:later_message_at) { 1.hour.ago.change(usec: 0) }

  before do
    create(:message, account: account, inbox: inbox, conversation: conversation, sender: contact,
                     source_id: 'first-message', created_at: first_message_at)
    create(:message, account: account, inbox: inbox, conversation: conversation, sender: contact,
                     source_id: 'later-message', created_at: later_message_at)
    conversation.update_columns(agent_last_seen_at: 3.hours.ago, assignee_last_seen_at: 3.hours.ago)
  end

  it 'marks only messages up to the WhatsApp read cursor as read' do
    described_class.new(inbox: inbox, params: {
                          chat: '123456789012345@lid', phone_jid: contact_inbox.source_id,
                          read: true, timestamp: Time.current.to_i, message_at: first_message_at.to_i
                        }).perform

    expect(conversation.reload.agent_last_seen_at.to_i).to eq(first_message_at.to_i)
    expect(conversation.unread_incoming_messages.count).to eq(1)
  end

  it 'does not let an older read event override a newer one' do
    now = Time.current.to_i
    service = lambda do |event_at, message_at|
      described_class.new(inbox: inbox, params: {
                            chat: contact_inbox.source_id, read: true,
                            timestamp: event_at, message_at: message_at
                          }).perform
    end

    service.call(now, later_message_at.to_i)
    service.call(now - 60, first_message_at.to_i)

    expect(conversation.reload.agent_last_seen_at.to_i).to eq(later_message_at.to_i)
    expect(conversation.unread_incoming_messages.count).to eq(0)
  end

  it 'uses message IDs from a read-self receipt when there is no cursor timestamp' do
    described_class.new(inbox: inbox, params: {
                          chat: contact_inbox.source_id, read: true,
                          timestamp: Time.current.to_i, message_ids: ['first-message']
                        }).perform

    expect(conversation.reload.agent_last_seen_at.to_i).to eq(first_message_at.to_i)
    expect(conversation.unread_incoming_messages.count).to eq(1)
  end

  it 'uses the latest known message when a WhatsApp read action has no message range' do
    described_class.new(inbox: inbox, params: {
                          chat: contact_inbox.source_id, read: true,
                          timestamp: Time.current.to_i
                        }).perform

    expect(conversation.reload.agent_last_seen_at.to_i).to eq(later_message_at.to_i)
    expect(conversation.unread_incoming_messages.count).to eq(0)
  end

  it 'reopens the latest incoming message when WhatsApp marks the chat unread' do
    described_class.new(inbox: inbox, params: {
                          chat: contact_inbox.source_id, read: false,
                          timestamp: Time.current.to_i, message_at: later_message_at.to_i
                        }).perform

    expect(conversation.reload.agent_last_seen_at).to be < later_message_at
    expect(conversation.unread_incoming_messages.count).to eq(1)
  end
end
