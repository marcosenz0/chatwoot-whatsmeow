require 'rails_helper'

RSpec.describe TelegramPersonal::IncomingEventService do
  let(:channel) { create(:channel_telegram_personal) }
  let(:inbox) { channel.inbox }
  let(:payload) do
    { 'event' => 'message', 'source_id' => '42:100', 'chat_id' => '42', 'chat_name' => 'Test Customer',
      'date' => Time.current.to_i, 'content' => 'Hello', 'outgoing' => false }
  end

  it 'imports an incoming message exactly once when callbacks are retried' do
    2.times { described_class.new(inbox: inbox, payload: payload).perform }
    expect(inbox.messages.where(source_id: '42:100').count).to eq(1)
    expect(inbox.contact_inboxes.last.source_id).to eq('42')
    expect(inbox.messages.last.sender.name).to eq('Test Customer')
  end

  it 'isolates matching Telegram ids in separate accounts' do
    other = create(:channel_telegram_personal).inbox
    [inbox, other].each { |target| described_class.new(inbox: target, payload: payload).perform }
    expect(inbox.messages.count).to eq(1)
    expect(other.messages.count).to eq(1)
    expect(inbox.contacts.last).not_to eq(other.contacts.last)
  end

  it 'merges a sending echo into the original outgoing message' do
    message = create(:message, message_type: :outgoing, content: 'Hello', inbox: inbox,
                               conversation: create(:conversation, inbox: inbox, account: inbox.account))
    described_class.new(inbox: inbox, payload: payload.merge('outgoing' => true, 'chatwoot_message_id' => message.id)).perform
    expect(inbox.messages.count).to eq(1)
    expect(message.reload.source_id).to eq('42:100')
  end

  it 'imports phone replies with source ids so they are not sent back to Telegram' do
    described_class.new(inbox: inbox, payload: payload.merge('outgoing' => true)).perform
    expect(inbox.messages.last).to be_outgoing
    expect(inbox.messages.last.source_id).to eq('42:100')
    expect(inbox.messages.last.sender).to be_nil
  end

  it 'ignores groups until the inbox explicitly enables them' do
    described_class.new(inbox: inbox, payload: payload.merge('group' => true)).perform
    expect(inbox.messages).to be_empty
    channel.update!(ignore_groups: false)
    described_class.new(inbox: inbox, payload: payload.merge('group' => true)).perform
    expect(inbox.messages.count).to eq(1)
  end

  it 'imports attachments from the authenticated service into account storage' do
    client = instance_double(TelegramPersonal::SessionClient, download_media: 'file contents')
    allow(TelegramPersonal::SessionClient).to receive(:new).with(inbox: inbox).and_return(client)
    data = payload.merge('attachments' => [{ 'id' => 'a' * 32, 'filename' => 'test.txt', 'content_type' => 'text/plain' }])
    described_class.new(inbox: inbox, payload: data).perform
    attachment = inbox.messages.last.attachments.last
    expect(attachment.file.download).to eq('file contents')
    expect(attachment.account_id).to eq(inbox.account_id)
  end

  it 'ignores broadcast channels separately from groups and identifies received history' do
    described_class.new(inbox: inbox, payload: payload.merge('channel' => true)).perform
    expect(inbox.messages).to be_empty
    channel.update!(ignore_channels: false)
    described_class.new(inbox: inbox, payload: payload.merge('channel' => true)).perform
    expect(inbox.messages.last.conversation.additional_attributes['telegram_channel']).to be(true)
    expect(channel).to be_ignore_groups
  end

  it 'retains the edit with the latest timestamp when old events are retried' do
    described_class.new(inbox: inbox, payload: payload).perform
    edit = { 'event' => 'edit', 'source_id' => '42:100', 'content' => 'New text', 'date' => 1000 }
    described_class.new(inbox: inbox, payload: edit).perform
    described_class.new(inbox: inbox, payload: edit.merge('content' => 'Old text', 'date' => 900)).perform
    expect(inbox.messages.last.content).to eq('New text')
  end

  it 'marks Telegram deletions and reading without changing private notes' do
    described_class.new(inbox: inbox, payload: payload.merge('outgoing' => true)).perform
    message = inbox.messages.last
    private_note = create(:message, private: true, inbox: inbox, account: inbox.account, conversation: message.conversation)
    described_class.new(inbox: inbox, payload: { 'event' => 'read', 'chat_id' => '42', 'max_id' => 100 }).perform
    expect(message.reload).to be_read
    expect(private_note.reload).not_to be_read
    described_class.new(inbox: inbox, payload: { 'event' => 'delete', 'source_ids' => ['42:100'] }).perform
    expect(message.reload.content_attributes['deleted_on_telegram']).to be(true)
    expect(message.content).to eq('Hello')
  end
end
