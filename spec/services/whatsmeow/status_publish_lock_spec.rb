require 'rails_helper'

RSpec.describe Whatsmeow::StatusPublishLock do
  let(:status) { WhatsmeowStatus.new(account_id: 7, session_key: 'phone:5563999993001') }
  let(:lock) { described_class.new(status: status) }
  let(:account_mutex_key) { 'whatsmeow:status-publish:account:7:mutex' }
  let(:account_cooldown_key) { 'whatsmeow:status-publish:account:7:cooldown' }
  let(:session_mutex_key) { 'whatsmeow:status-publish:phone:5563999993001:mutex' }
  let(:session_cooldown_key) { 'whatsmeow:status-publish:phone:5563999993001:cooldown' }

  before do
    allow(Redis::Alfred).to receive(:ttl).and_return(0)
    allow(Redis::Alfred).to receive(:set).and_return(true)
    allow(Redis::Alfred).to receive(:delete_if_equals).and_return(true)
    allow(Rails.logger).to receive(:error)
  end

  it 'limits mutex contention polling to five seconds' do
    allow(Redis::Alfred).to receive(:set).with(account_mutex_key, anything, nx: true, ex: anything).and_return(false)
    allow(Redis::Alfred).to receive(:ttl).with(account_mutex_key).and_return(120)

    expect(lock.acquire).to eq(5)
  end

  it 'releases acquired mutexes when setting a cooldown fails' do
    expect(lock.acquire).to eq(0)
    allow(Redis::Alfred).to receive(:set)
      .with(session_cooldown_key, anything, ex: described_class::SESSION_INTERVAL.to_i)
      .and_raise(StandardError, 'redis unavailable')

    expect { lock.finish }.to raise_error(StandardError, 'redis unavailable')
    expect(Redis::Alfred).to have_received(:delete_if_equals).with(account_mutex_key, anything)
    expect(Redis::Alfred).to have_received(:delete_if_equals).with(session_mutex_key, anything)
  end

  it 'continues releasing the remaining mutex when one delete fails' do
    expect(lock.acquire).to eq(0)
    allow(Redis::Alfred).to receive(:delete_if_equals)
      .with(account_mutex_key, anything)
      .and_raise(StandardError, 'redis unavailable')

    expect { lock.release }.not_to raise_error
    expect(Redis::Alfred).to have_received(:delete_if_equals).with(session_mutex_key, anything)
    expect(Rails.logger).to have_received(:error).with(include(account_mutex_key))
  end
end
