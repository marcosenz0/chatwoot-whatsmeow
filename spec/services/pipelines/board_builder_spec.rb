# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Pipelines::BoardBuilder do
  describe '#perform' do
    let(:account) { create(:account) }
    let(:admin) { create(:user, account: account, role: :administrator) }
    let(:pipeline) { create(:conversation_pipeline, account: account) }
    let!(:new_stage) do
      create(:conversation_pipeline_stage, conversation_pipeline: pipeline, name: 'Novo lead', position: 0, stale_after_days: 1)
    end
    let!(:qualified_stage) do
      create(:conversation_pipeline_stage, conversation_pipeline: pipeline, name: 'Qualificado', position: 1)
    end

    it 'groups conversations by stage with counts and stale counts' do
      stale_conversation = create(
        :conversation,
        account: account,
        conversation_pipeline: pipeline,
        conversation_pipeline_stage: new_stage,
        pipeline_stage_entered_at: 2.days.ago
      )
      create(
        :conversation,
        account: account,
        conversation_pipeline: pipeline,
        conversation_pipeline_stage: qualified_stage,
        pipeline_stage_entered_at: Time.current
      )

      board = described_class.new(account: account, user: admin, pipeline: pipeline, params: { per_page: 25 }).perform
      first_stage = board[:stages].first

      expect(board[:total_count]).to eq(2)
      expect(first_stage[:id]).to eq(new_stage.id)
      expect(first_stage[:count]).to eq(1)
      expect(first_stage[:stale_count]).to eq(1)
      expect(first_stage[:conversations].first[:id]).to eq(stale_conversation.display_id)
    end

    it 'supports per-stage pagination' do
      create_list(
        :conversation,
        2,
        account: account,
        conversation_pipeline: pipeline,
        conversation_pipeline_stage: new_stage,
        pipeline_stage_entered_at: Time.current
      )

      board = described_class.new(
        account: account,
        user: admin,
        pipeline: pipeline,
        params: { per_page: 1, stage_pages: { new_stage.id.to_s => 1 } }
      ).perform

      first_stage = board[:stages].first
      expect(first_stage[:conversations].size).to eq(1)
      expect(first_stage[:pagination]).to include(current_page: 1, next_page: 2, total_pages: 2)
    end
  end
end
