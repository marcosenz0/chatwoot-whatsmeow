require 'rails_helper'

RSpec.describe Whatsmeow::RecoverStatusPublicationsJob, type: :job do
  let(:account) { create(:account) }
  let(:first_channel) { create(:channel_whatsmeow, account: account, phone_number: '+5563999992001') }
  let(:second_channel) { create(:channel_whatsmeow, account: account, phone_number: '+5563999992002') }
  let(:publication_id) { SecureRandom.uuid }

  before { clear_enqueued_jobs }

  it 'leases and enqueues the earliest queued delivery' do
    first_status = create_status(inbox: first_channel.inbox, position: 0, state: :queued)
    second_status = create_status(inbox: second_channel.inbox, position: 1, state: :queued)

    described_class.perform_now

    expect(Whatsmeow::PublishStatusJob).to have_been_enqueued.with(first_status.id)
    expect(Whatsmeow::PublishStatusJob).not_to have_been_enqueued.with(second_status.id)
    expect(enqueued_jobs.size).to eq(1)
    expect(first_status.reload.next_attempt_at).to be_within(2.seconds).of(described_class::LEASE_DURATION.from_now)
    expect(second_status.reload.next_attempt_at).to be_nil
  end

  it 'does not skip a fresh processing delivery to enqueue a later position' do
    create_status(inbox: first_channel.inbox, position: 0, state: :processing)
    create_status(inbox: second_channel.inbox, position: 1, state: :queued)

    described_class.perform_now

    expect(enqueued_jobs).to be_empty
  end

  it 'requeues a stale processing delivery and resumes from that same position' do
    stale_status = create_status(inbox: first_channel.inbox, position: 0, state: :processing)
    second_status = create_status(inbox: second_channel.inbox, position: 1, state: :queued)
    stale_status.update!(updated_at: (described_class::STALE_AFTER + 1.minute).ago)

    described_class.perform_now

    expect(stale_status.reload).to be_publication_queued
    expect(Whatsmeow::PublishStatusJob).to have_been_enqueued.with(stale_status.id)
    expect(Whatsmeow::PublishStatusJob).not_to have_been_enqueued.with(second_status.id)
    expect(enqueued_jobs.size).to eq(1)
  end

  private

  def create_status(inbox:, position:, state:)
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
      publication_state: state
    )
  end
end
