# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Pipelines::CandidateBuilder do
  describe '#perform' do
    let(:account) { create(:account) }
    let(:admin) { create(:user, account: account, role: :administrator) }
    let(:pipeline) { create(:conversation_pipeline, account: account) }

    it 'returns conversations that are not already in the selected pipeline' do
      candidate = create(:conversation, account: account)
      create(:conversation, account: account, conversation_pipeline: pipeline)

      result = described_class.new(account: account, user: admin, pipeline: pipeline, params: {}).perform

      expect(result[:conversations].pluck(:uuid)).to include(candidate.uuid)
      expect(result[:meta][:count]).to eq(1)
    end

    it 'excludes Whatsmeow group conversations by default' do
      group_contact = create(:contact, account: account, additional_attributes: { whatsmeow_group: true })
      group_conversation = create(:conversation, account: account, contact: group_contact)

      result = described_class.new(account: account, user: admin, pipeline: pipeline, params: {}).perform
      result_with_groups = described_class.new(
        account: account,
        user: admin,
        pipeline: pipeline,
        params: { include_groups: true }
      ).perform

      expect(result[:conversations].pluck(:uuid)).not_to include(group_conversation.uuid)
      expect(result_with_groups[:conversations].pluck(:uuid)).to include(group_conversation.uuid)
    end

    it 'searches by contact and message content' do
      contact = create(:contact, account: account, name: 'Lead Meta Agosto')
      conversation = create(:conversation, account: account, contact: contact)
      create(:message, account: account, conversation: conversation, content: 'Quer fazer locucao para campanha')

      result_by_contact = described_class.new(account: account, user: admin, pipeline: pipeline, params: { q: 'Meta Agosto' }).perform
      result_by_message = described_class.new(account: account, user: admin, pipeline: pipeline, params: { q: 'locucao' }).perform

      expect(result_by_contact[:conversations].pluck(:uuid)).to eq([conversation.uuid])
      expect(result_by_message[:conversations].pluck(:uuid)).to eq([conversation.uuid])
    end
  end
end
