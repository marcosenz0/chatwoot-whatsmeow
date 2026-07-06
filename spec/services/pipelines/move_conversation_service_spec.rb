# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Pipelines::MoveConversationService do
  describe '#perform' do
    let(:account) { create(:account) }
    let(:pipeline) { create(:conversation_pipeline, account: account) }
    let(:stage) { create(:conversation_pipeline_stage, conversation_pipeline: pipeline) }
    let(:conversation) { create(:conversation, account: account) }

    it 'moves a conversation to the selected stage and pipeline' do
      described_class.new(account: account, conversation: conversation, stage: stage).perform

      expect(conversation.reload.conversation_pipeline).to eq(pipeline)
      expect(conversation.conversation_pipeline_stage).to eq(stage)
      expect(conversation.pipeline_stage_entered_at).to be_present
    end

    it 'rejects a stage from another account' do
      other_stage = create(:conversation_pipeline_stage)

      expect do
        described_class.new(account: account, conversation: conversation, stage: other_stage).perform
      end.to raise_error(ActiveRecord::RecordNotFound)
    end

    it 'rejects a conversation from another account' do
      other_conversation = create(:conversation)

      expect do
        described_class.new(account: account, conversation: other_conversation, stage: stage).perform
      end.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
