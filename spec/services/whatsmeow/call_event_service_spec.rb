require 'rails_helper'

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
  end

  it 'keeps one completed call when webhook events arrive out of order or repeat' do
    outgoing = base_params.merge('direction' => 'outgoing', 'video' => true)
    described_class.new(inbox: inbox, params: outgoing.merge('event' => 'call_ended', 'timestamp' => 1_780_000_020,
                                                              'connected_at' => 1_780_000_010)).perform
    described_class.new(inbox: inbox, params: outgoing.merge('event' => 'call_started')).perform
    described_class.new(inbox: inbox, params: outgoing.merge('event' => 'call_ended', 'timestamp' => 1_780_000_021)).perform

    call = WhatsmeowCall.find_by!(inbox: inbox, source_id: 'test-call-1')
    expect(call).to have_attributes(status: 'completed', direction: 'outgoing', video: true)
    expect(call.started_at.to_i).to eq(1_780_000_000)
    expect(call.duration_seconds).to eq(10)
    expect(WhatsmeowCall.where(inbox: inbox, source_id: 'test-call-1').count).to eq(1)
  end
end
