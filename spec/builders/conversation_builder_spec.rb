require 'rails_helper'

describe ConversationBuilder do
  let(:account) { create(:account) }
  let!(:sms_channel) { create(:channel_sms, account: account) }
  let!(:api_channel) { create(:channel_api, account: account) }
  let!(:sms_inbox) { create(:inbox, channel: sms_channel, account: account) }
  let!(:api_inbox) { create(:inbox, channel: api_channel, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_sms_inbox) { create(:contact_inbox, contact: contact, inbox: sms_inbox) }
  let(:contact_api_inbox) { create(:contact_inbox, contact: contact, inbox: api_inbox) }

  describe '#perform' do
    it 'creates sms conversation' do
      conversation = described_class.new(
        contact_inbox: contact_sms_inbox,
        params: {}
      ).perform

      expect(conversation.contact_inbox_id).to eq(contact_sms_inbox.id)
    end

    it 'creates api conversation' do
      conversation = described_class.new(
        contact_inbox: contact_api_inbox,
        params: {}
      ).perform

      expect(conversation.contact_inbox_id).to eq(contact_api_inbox.id)
    end

    context 'with a verified alternate Whatsmeow phone in the same inbox' do
      let(:inbox) { create(:channel_whatsmeow, account: account).inbox }
      let(:registered_lid) { '123456789@lid' }
      let(:canonical_contact) { create(:contact, account: account, phone_number: '+556398765432') }
      let(:alternate_contact) { create(:contact, account: account, phone_number: '+5563998765432') }
      let(:canonical_inbox) do
        create(:contact_inbox, inbox: inbox, contact: canonical_contact, source_id: '556398765432@s.whatsapp.net')
      end
      let(:alternate_inbox) do
        create(:contact_inbox, inbox: inbox, contact: alternate_contact, source_id: '5563998765432@s.whatsapp.net')
      end

      it 'continues the original direct conversation' do
        existing = create(:conversation, account: account, inbox: inbox, contact: canonical_contact, contact_inbox: canonical_inbox)
        client = instance_double(Whatsmeow::SessionClient)
        allow(Whatsmeow::SessionClient).to receive(:new).with(inbox: inbox).and_return(client)
        allow(client).to receive(:check_number).with('+5563998765432').and_return({ 'is_on_whatsapp' => true, 'jid' => registered_lid })
        allow(client).to receive(:check_number).with('+556398765432').and_return({ 'is_on_whatsapp' => true, 'jid' => registered_lid })

        expect(described_class.new(params: {}, contact_inbox: alternate_inbox).perform).to eq(existing)
        expect(inbox.conversations.where.not(status: :resolved).count).to eq(1)
      end
    end


    context 'when lock_to_single_conversation is true for sms inbox' do
      before do
        sms_inbox.update!(lock_to_single_conversation: true)
      end

      it 'creates sms conversation when existing conversation is not present' do
        conversation = described_class.new(
          contact_inbox: contact_sms_inbox,
          params: {}
        ).perform

        expect(conversation.contact_inbox_id).to eq(contact_sms_inbox.id)
      end

      it 'returns last from existing sms conversations when existing conversation is not present' do
        create(:conversation, contact_inbox: contact_sms_inbox)
        existing_conversation = create(:conversation, contact_inbox: contact_sms_inbox)
        conversation = described_class.new(
          contact_inbox: contact_sms_inbox,
          params: {}
        ).perform

        expect(conversation.id).to eq(existing_conversation.id)
      end
    end

    context 'when lock_to_single_conversation is true for api inbox' do
      before do
        api_inbox.update!(lock_to_single_conversation: true)
      end

      it 'creates conversation when existing api conversation is not present' do
        conversation = described_class.new(
          contact_inbox: contact_api_inbox,
          params: {}
        ).perform

        expect(conversation.contact_inbox_id).to eq(contact_api_inbox.id)
      end

      it 'returns last from existing api conversations when existing conversation is not present' do
        create(:conversation, contact_inbox: contact_api_inbox)
        existing_conversation = create(:conversation, contact_inbox: contact_api_inbox)
        conversation = described_class.new(
          contact_inbox: contact_api_inbox,
          params: {}
        ).perform

        expect(conversation.id).to eq(existing_conversation.id)
      end
    end
  end
end
