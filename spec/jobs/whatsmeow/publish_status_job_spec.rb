require 'rails_helper'

RSpec.describe Whatsmeow::PublishStatusJob, type: :job do
  let(:account) { create(:account) }
  let(:first_channel) { create(:channel_whatsmeow, account: account, phone_number: '+5563999991001') }
  let(:second_channel) { create(:channel_whatsmeow, account: account, phone_number: '+5563999991002') }
  let(:publication_id) { SecureRandom.uuid }
  let!(:first_status) { create_status(inbox: first_channel.inbox, position: 0) }
  let!(:second_status) { create_status(inbox: second_channel.inbox, position: 1) }
  let(:publish_lock) { instance_spy(Whatsmeow::StatusPublishLock, acquire: 0) }
  let(:session_client) { instance_double(Whatsmeow::SessionClient) }

  before do
    clear_enqueued_jobs
    allow(Whatsmeow::StatusPublishLock).to receive(:new).with(status: first_status).and_return(publish_lock)
    allow(Whatsmeow::SessionClient).to receive(:new).with(inbox: first_status.inbox).and_return(session_client)
  end

  it 'publishes with the persisted source ID and enqueues the next delivery position' do
    response = {
      'id' => first_status.source_id,
      'timestamp' => Time.current.to_i,
      'jid' => first_status.sender_jid
    }
    expect(session_client).to receive(:publish_status)
      .with(hash_including(message_id: first_status.source_id))
      .and_return(response)

    described_class.perform_now(first_status.id)

    expect(first_status.reload).to be_publication_published
    expect(first_status.publish_attempts).to eq(1)
    expect(second_status.reload).to be_publication_queued
    expect(described_class).to have_been_enqueued.with(second_status.id)
    expect(enqueued_jobs.size).to eq(1)
    expect(publish_lock).to have_received(:finish)
  end

  it 'marks a permanent infrastructure failure as failed on the last attempt and advances the publication' do
    publisher = instance_double(Whatsmeow::StatusPublisher)
    first_status.update!(publish_attempts: described_class::MAX_ATTEMPTS - 1)
    allow(Whatsmeow::StatusPublisher).to receive(:new).with(status: first_status).and_return(publisher)
    allow(publisher).to receive(:perform).and_raise(ArgumentError, 'invalid persisted media')

    expect { described_class.perform_now(first_status.id) }.not_to raise_error

    expect(first_status.reload).to be_publication_failed
    expect(first_status.publish_attempts).to eq(described_class::MAX_ATTEMPTS)
    expect(first_status.last_error).to eq('invalid persisted media')
    expect(described_class).to have_been_enqueued.with(second_status.id)
  end

  private

  def create_status(inbox:, position:)
    phone = inbox.channel.phone_number.delete('^0-9')
    WhatsmeowStatus.create!(
      account: account,
      inbox: inbox,
      source_id: "3EB0#{SecureRandom.hex(9).upcase}",
      sender_jid: "#{phone}@s.whatsapp.net",
      sender_name: inbox.name,
      sender_phone: inbox.channel.phone_number,
      status_type: :text,
      content: "Status #{position}",
      from_me: true,
      posted_at: Time.current,
      expires_at: 24.hours.from_now,
      metadata: { 'publication_id' => publication_id },
      publication_id: publication_id,
      session_key: "phone:#{phone}",
      publication_position: position,
      publication_state: :queued
    )
  end
end
