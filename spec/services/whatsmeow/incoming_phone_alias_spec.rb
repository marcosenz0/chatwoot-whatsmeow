require 'rails_helper'

RSpec.describe Whatsmeow::IncomingMessageService do
  subject(:receive_reply) { inbox.with_lock { described_class.new(inbox: inbox, params: params).perform } }

  let(:account) { create(:account) }
  let(:inbox) { create(:channel_whatsmeow, account: account).inbox }
  let(:typed_phone) { '+5563998765432' }
  let(:wire_phone) { '+556398765432' }
  let(:peer_lid) { '123456789@lid' }
  let(:typed_contact) { create(:contact, account: account, phone_number: typed_phone, name: typed_phone) }
  let(:typed_inbox) { create(:contact_inbox, inbox: inbox, contact: typed_contact, source_id: '5563998765432@s.whatsapp.net') }
  let!(:outbound_thread) { create(:conversation, account: account, inbox: inbox, contact: typed_contact, contact_inbox: typed_inbox) }
  let!(:outbound) do
    create(:message, account: account, inbox: inbox, conversation: outbound_thread,
                     message_type: :outgoing, status: :delivered, source_id: 'outbound-provider-id')
  end
  let(:client) { instance_double(Whatsmeow::SessionClient) }
  let(:registered_jid) { peer_lid }
  let(:params) do
    {
      contact_jid: '556398765432@s.whatsapp.net',
      contact_phone: wire_phone,
      contact_lid_jid: peer_lid,
      sender_name: 'Example Solar',
      message_id: 'incoming-provider-id',
      content: 'Received your message',
      timestamp: Time.current.to_i
    }.with_indifferent_access
  end

  before do
    allow(Whatsmeow::SessionClient).to receive(:new).with(inbox: inbox).and_return(client)
    allow(client).to receive(:check_number).with(typed_phone).and_return({ 'is_on_whatsapp' => true, 'jid' => registered_jid })
  end

  it 'puts a reply under the original outgoing history when WhatsApp confirms the phone alias' do
    expect { receive_reply }.not_to change(inbox.conversations, :count)
    expect(outbound.reload).to have_attributes(conversation_id: outbound_thread.id, status: 'delivered')
    expect(inbox.messages.find_by!(source_id: params[:message_id]).conversation_id).to eq(outbound_thread.id)
    expect(outbound_thread.reload.contact_inbox.source_id).to eq(params[:contact_jid])
    expect(client).to have_received(:check_number).with(typed_phone).once
  end

  context 'when an earlier reply already created a separate history' do
    let(:wire_contact) { create(:contact, account: account, phone_number: wire_phone, name: 'Example Solar') }
    let(:wire_inbox) { create(:contact_inbox, inbox: inbox, contact: wire_contact, source_id: params[:contact_jid]) }
    let!(:duplicate) do
      create(:conversation, account: account, inbox: inbox, contact: wire_contact, contact_inbox: wire_inbox, created_at: 1.minute.from_now)
    end
    let!(:prior_reply) { create(:message, account: account, inbox: inbox, conversation: duplicate, sender: wire_contact) }

    it 'moves the reply history while preserving the original display ID and message IDs' do
      expect { receive_reply }.to change(inbox.conversations, :count).by(-1)
      expect(prior_reply.reload.conversation_id).to eq(outbound_thread.id)
      expect(outbound_thread.reload.contact.name).to eq('Example Solar')
      expect(outbound.reload.conversation_id).to eq(outbound_thread.id)
    end
  end

  context 'when WhatsApp returns another account' do
    let(:registered_jid) { '987654321@lid' }

    it 'keeps the two histories separate' do
      expect { receive_reply }.to change(inbox.conversations, :count).by(1)
      expect(outbound.reload.conversation_id).to eq(outbound_thread.id)
      expect(inbox.messages.find_by!(source_id: params[:message_id]).conversation_id).not_to eq(outbound_thread.id)
    end
  end
end
