require 'rails_helper'

RSpec.describe Message, '#send_reply' do
  let(:message) { build_stubbed(:message) }

  before do
    allow(message).to receive_messages(
      attachments: [instance_double(Attachment)],
      content_attributes: {},
      inbox: instance_double(Inbox, channel_type: 'Channel::Whatsmeow')
    )
  end

  it 'enqueues Whatsmeow attachments immediately' do
    allow(SendReplyJob).to receive(:perform_later)

    message.send(:send_reply)

    expect(SendReplyJob).to have_received(:perform_later).with(message.id)
  end
end
