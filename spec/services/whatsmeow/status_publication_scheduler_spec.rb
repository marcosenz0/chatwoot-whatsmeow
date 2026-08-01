require 'rails_helper'

RSpec.describe Whatsmeow::StatusPublicationScheduler do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:publication_id) { SecureRandom.uuid }
  let!(:first_alias_channel) do
    create(:channel_whatsmeow, account: account, phone_number: '+5563999990001')
  end
  let!(:second_alias_channel) do
    create(:channel_whatsmeow, account: account, phone_number: '+5563999990001')
  end
  let!(:other_channel) do
    create(:channel_whatsmeow, account: account, phone_number: '+5563999990002')
  end
  let(:inboxes) { [first_alias_channel.inbox, second_alias_channel.inbox, other_channel.inbox] }
  let(:params) do
    {
      publication_id: publication_id,
      content: 'Status em segundo plano',
      background: 'blue',
      font: 'bold'
    }
  end

  before { clear_enqueued_jobs }

  describe '#perform' do
    it 'creates queued deliveries and deduplicates aliases from the same phone session', :aggregate_failures do
      statuses = perform_scheduler(params)
      aliases = statuses.select { |status| status.inbox_id.in?([first_alias_channel.inbox.id, second_alias_channel.inbox.id]) }
      other = statuses.find { |status| status.inbox_id == other_channel.inbox.id }

      expect(statuses.size).to eq(3)
      expect(statuses).to all(be_publication_queued)
      expect(statuses.map(&:publication_id).uniq).to eq([publication_id])
      expect(aliases.map(&:source_id).uniq.one?).to be(true)
      expect(aliases.map(&:session_key).uniq.one?).to be(true)
      expect(aliases.map(&:publication_position).uniq).to eq([0])
      expect(other.publication_position).to eq(1)
      expect(other.source_id).not_to eq(aliases.first.source_id)
      expect(Whatsmeow::PublishStatusJob).to have_been_enqueued.with(aliases.map(&:id).min)
      expect(enqueued_jobs.size).to eq(1)
    end

    it 'returns the original deliveries when the publication UUID is reused with the same payload' do
      original_statuses = perform_scheduler(params)
      clear_enqueued_jobs

      repeated_statuses = perform_scheduler(params)

      expect(repeated_statuses.map(&:id)).to eq(original_statuses.map(&:id))
      expect(account.whatsmeow_statuses.where(publication_id: publication_id).count).to eq(3)
      expect(Whatsmeow::PublishStatusJob).to have_been_enqueued.with(original_statuses.map(&:id).min)
      expect(enqueued_jobs.size).to eq(1)
    end

    it 'rejects a reused publication UUID when the payload fingerprint changes' do
      perform_scheduler(params)
      changed_params = params.merge(content: 'Outro conteúdo')

      expect do
        perform_scheduler(changed_params)
      end.to raise_error(ArgumentError, /different Status content/)

      expect(account.whatsmeow_statuses.where(publication_id: publication_id).count).to eq(3)
    end

    it 'keeps legacy single-inbox requests idempotent across aliases of the same phone session' do
      legacy_params = params.merge(legacy_single_inbox: true)
      first_statuses = described_class.new(inboxes: [first_alias_channel.inbox], user: user, params: legacy_params).perform
      clear_enqueued_jobs

      repeated_statuses = described_class.new(inboxes: [second_alias_channel.inbox], user: user, params: legacy_params).perform

      expect(repeated_statuses.map(&:id)).to eq(first_statuses.map(&:id))
      expect(account.whatsmeow_statuses.where(publication_id: publication_id).count).to eq(1)
      expect(Whatsmeow::PublishStatusJob).to have_been_enqueued.with(first_statuses.first.id)
    end
  end

  private

  def perform_scheduler(scheduler_params)
    described_class.new(inboxes: inboxes, user: user, params: scheduler_params).perform
  end
end
