require 'rails_helper'

RSpec.describe Whatsmeow::TypingStatusService do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_whatsmeow, account: account, typing_enabled: true) }
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: account, phone_number: '+556399999999') }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: '556391189840@s.whatsapp.net') }
  let(:conversation) do
    create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
  end

  describe '#perform' do
    let(:client) { instance_double(Whatsmeow::SessionClient, typing: {}) }

    before do
      allow(Whatsmeow::SessionClient).to receive(:new).with(inbox: inbox).and_return(client)
    end

    it 'sends composing presence to the authoritative conversation source' do
      described_class.new(conversation: conversation, status: 'on').perform

      expect(client).to have_received(:typing).with(to: '556391189840@s.whatsapp.net', state: 'composing')
    end

    it 'sends paused presence when typing stops' do
      described_class.new(conversation: conversation, status: 'off').perform

      expect(client).to have_received(:typing).with(to: '556391189840@s.whatsapp.net', state: 'paused')
    end

    it 'does not send typing presence when the inbox setting is disabled' do
      channel.update!(typing_enabled: false)

      described_class.new(conversation: conversation, status: 'on').perform

      expect(client).not_to have_received(:typing)
    end
  end

  describe '.apply_incoming' do
    let(:dispatcher) { instance_double(Dispatcher) }

    before do
      allow(Rails.configuration).to receive(:dispatcher).and_return(dispatcher)
      allow(dispatcher).to receive(:dispatch)
      conversation
    end

    it 'publishes contact typing through the existing Chatwoot realtime event' do
      described_class.apply_incoming(
        inbox: inbox,
        params: { state: 'composing', chat: '556391189840@s.whatsapp.net', sender: '556391189840@s.whatsapp.net' }
      )

      expect(dispatcher).to have_received(:dispatch).with(
        Events::Types::CONVERSATION_TYPING_ON,
        kind_of(ActiveSupport::TimeWithZone),
        conversation: conversation,
        user: contact,
        is_private: false
      )
    end

    it 'publishes typing off when WhatsApp reports paused' do
      described_class.apply_incoming(
        inbox: inbox,
        params: { state: 'paused', chat: '556391189840@s.whatsapp.net', sender: '556391189840@s.whatsapp.net' }
      )

      expect(dispatcher).to have_received(:dispatch).with(
        Events::Types::CONVERSATION_TYPING_OFF,
        kind_of(ActiveSupport::TimeWithZone),
        conversation: conversation,
        user: contact,
        is_private: false
      )
    end
  end
end
