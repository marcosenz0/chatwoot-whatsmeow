require 'rails_helper'

RSpec.describe WhatsmeowListener do
  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:service) { instance_double(Whatsmeow::TypingStatusService, perform: nil) }

  before do
    allow(Whatsmeow::TypingStatusService).to receive(:new).and_return(service)
  end

  it 'forwards an agent typing event to the Whatsmeow service' do
    event = Events::Base.new(:'conversation.typing_on', Time.zone.now, conversation: conversation, user: agent, is_private: false)

    listener.conversation_typing_on(event)

    expect(Whatsmeow::TypingStatusService).to have_received(:new).with(conversation: conversation, status: 'on', media: nil)
    expect(service).to have_received(:perform)
  end

  it 'does not echo an incoming contact typing event back to WhatsApp' do
    event = Events::Base.new(
      :'conversation.typing_on', Time.zone.now, conversation: conversation, user: conversation.contact, is_private: false
    )

    listener.conversation_typing_on(event)

    expect(service).not_to have_received(:perform)
  end

  it 'does not expose private note typing' do
    event = Events::Base.new(:'conversation.typing_on', Time.zone.now, conversation: conversation, user: agent, is_private: true)

    listener.conversation_typing_on(event)

    expect(service).not_to have_received(:perform)
  end
end
