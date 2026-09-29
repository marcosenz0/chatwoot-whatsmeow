require 'rails_helper'
require Rails.root.join('db/migrate/20260929173000_backfill_whatsmeow_call_messages').to_s

RSpec.describe Whatsmeow::CallEventService do
  let(:account) { create(:account) }
  let(:inbox) { create(:channel_whatsmeow, account: account).inbox }
  let(:contact) { create(:contact, account: account, phone_number: '+5563999999999') }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5563999999999@s.whatsapp.net') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:base_params) do
    {
      'call_id' => 'test-call-1', 'peer_jid' => '123456789012345@lid',
      'phone_jid' => '5563999999999@s.whatsapp.net', 'direction' => 'incoming',
      'timestamp' => 1_780_000_000, 'video' => false
    }
  end

  it 'records a missed incoming call against the matching inbox and conversation' do
    conversation
    described_class.new(inbox: inbox, params: base_params.merge('event' => 'call_started')).perform
    described_class.new(inbox: inbox, params: base_params.merge('event' => 'call_ended', 'timestamp' => 1_780_000_015)).perform

    call = WhatsmeowCall.find_by!(inbox: inbox, source_id: 'test-call-1')
    expect(call).to have_attributes(status: 'missed', contact: contact, conversation: conversation)
    expect(call.duration_seconds).to eq(0)
    message = conversation.messages.find_by!(source_id: 'whatsmeow-call:test-call-1')
    expect(message).to have_attributes(content_type: 'voice_call', message_type: 'incoming', sender: contact)
    expect(message.content_attributes['whatsmeow_call']).to include('status' => 'missed', 'duration_seconds' => 0)
    expect(message.historical?).to be(true)
  end

  it 'keeps one completed call when webhook events arrive out of order or repeat' do
    conversation
    outgoing = base_params.merge('direction' => 'outgoing', 'video' => true)
    ended = outgoing.merge('event' => 'call_ended', 'timestamp' => 1_780_000_020, 'connected_at' => 1_780_000_010)
    described_class.new(inbox: inbox, params: ended).perform
    described_class.new(inbox: inbox, params: outgoing.merge('event' => 'call_started')).perform
    described_class.new(inbox: inbox, params: outgoing.merge('event' => 'call_ended', 'timestamp' => 1_780_000_021)).perform

    call = WhatsmeowCall.find_by!(inbox: inbox, source_id: 'test-call-1')
    expect(call).to have_attributes(status: 'completed', direction: 'outgoing', video: true)
    expect(call.started_at.to_i).to eq(1_780_000_000)
    expect(call.duration_seconds).to eq(10)
    expect(WhatsmeowCall.where(inbox: inbox, source_id: 'test-call-1').count).to eq(1)
    expect(conversation.messages.where(source_id: 'whatsmeow-call:test-call-1').count).to eq(1)
    message = conversation.messages.find_by!(source_id: 'whatsmeow-call:test-call-1')
    expect(message.content_attributes['whatsmeow_call']).to include('status' => 'completed', 'video' => true, 'duration_seconds' => 10)
    expect(message.created_at.to_i).to eq(1_780_000_000)
    expect(message.content_attributes['skip_send_reply_job']).to be(true)
  end

  it 'uses the signed conversation ID when the same contact has another conversation' do
    conversation
    create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
    params = base_params.merge('event' => 'call_ended', 'conversation_id' => conversation.id)

    expect { described_class.new(inbox: inbox, params: params).perform }.not_to have_enqueued_job(SendReplyJob)

    call = WhatsmeowCall.find_by!(inbox: inbox, source_id: 'test-call-1')
    expect(call.conversation).to eq(conversation)
    expect(conversation.messages.voice_calls.count).to eq(1)
  end

  it 'backfills existing calls idempotently without sending WhatsApp messages' do
    call = WhatsmeowCall.create!(account: account, inbox: inbox, conversation: conversation, contact: contact,
                                 source_id: 'old-call', peer_jid: '123456789012345@lid', direction: 'outgoing', status: 'completed', video: true,
                                 started_at: 3.minutes.ago, connected_at: 2.minutes.ago, ended_at: 1.minute.ago)
    migration = BackfillWhatsmeowCallMessages.new
    expect { 2.times { migration.migrate(:up) } }.not_to have_enqueued_job(SendReplyJob)

    expect(conversation.messages.where(source_id: 'whatsmeow-call:old-call').count).to eq(1)
    message = conversation.messages.find_by!(source_id: 'whatsmeow-call:old-call')
    expect(message.content_attributes['whatsmeow_call']).to include('id' => call.id, 'video' => true, 'duration_seconds' => 60)
    expect(message.historical?).to be(true)
  end
end
