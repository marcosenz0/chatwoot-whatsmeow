# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ConversationPipelineStage do
  describe 'validations and defaults' do
    it 'inherits the account from its pipeline' do
      pipeline = create(:conversation_pipeline)
      stage = described_class.create!(conversation_pipeline: pipeline, name: 'Proposta enviada')

      expect(stage.account).to eq(pipeline.account)
      expect(stage.internal_name).to eq('proposta_enviada')
      expect(stage.color).to eq(described_class::DEFAULT_COLOR)
    end

    it 'validates that account matches the pipeline account' do
      pipeline = create(:conversation_pipeline)
      stage = build(:conversation_pipeline_stage, conversation_pipeline: pipeline, account: create(:account))

      expect(stage).not_to be_valid
      expect(stage.errors[:account_id]).to include('must match pipeline account')
    end

    it 'allows reusing the visible name after a stage is archived' do
      pipeline = create(:conversation_pipeline)
      create(:conversation_pipeline_stage, conversation_pipeline: pipeline, name: 'Proposta enviada', archived: true)

      stage = described_class.create!(conversation_pipeline: pipeline, name: 'Proposta enviada')

      expect(stage.internal_name).to eq('proposta_enviada')
    end
  end

  describe '#push_event_data' do
    it 'returns stage fields used by UI and webhooks' do
      stage = create(:conversation_pipeline_stage, name: 'Ganho', category: 'won', probability: 100)

      expect(stage.push_event_data).to include(
        id: stage.id,
        name: 'Ganho',
        internal_name: 'ganho',
        category: 'won',
        probability: 100
      )
    end
  end
end
