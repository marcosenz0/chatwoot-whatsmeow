# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ConversationPipeline do
  describe 'validations and defaults' do
    let(:account) { create(:account) }

    it 'normalizes the internal name and assigns the next position' do
      create(:conversation_pipeline, account: account, position: 0)

      pipeline = described_class.create!(account: account, name: 'Lead campanha Meta')

      expect(pipeline.internal_name).to eq('lead_campanha_meta')
      expect(pipeline.position).to eq(1)
      expect(pipeline.color).to eq(described_class::DEFAULT_COLOR)
    end

    it 'keeps one default pipeline per account' do
      first_pipeline = create(:conversation_pipeline, account: account, default: true)
      second_pipeline = create(:conversation_pipeline, account: account, default: true)

      expect(first_pipeline.reload.default).to be(false)
      expect(second_pipeline.reload.default).to be(true)
    end
  end

  describe '#push_event_data' do
    it 'returns active stages in board order' do
      pipeline = create(:conversation_pipeline)
      active_stage = create(:conversation_pipeline_stage, conversation_pipeline: pipeline, position: 0)
      create(:conversation_pipeline_stage, conversation_pipeline: pipeline, archived: true, position: 1)

      expect(pipeline.push_event_data).to include(
        id: pipeline.id,
        name: pipeline.name,
        internal_name: pipeline.internal_name,
        stages: [active_stage.push_event_data]
      )
    end
  end
end
