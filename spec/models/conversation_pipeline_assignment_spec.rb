# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Conversation do
  describe 'pipeline assignment' do
    let(:account) { create(:account) }
    let(:pipeline) { create(:conversation_pipeline, account: account, default: true) }
    let!(:stage) { create(:conversation_pipeline_stage, conversation_pipeline: pipeline, position: 0) }

    it 'does not assign new conversations to the account default pipeline stage automatically' do
      conversation = create(:conversation, account: account)

      expect(conversation.conversation_pipeline).to be_nil
      expect(conversation.conversation_pipeline_stage).to be_nil
      expect(conversation.pipeline_stage_entered_at).to be_nil
    end

    it 'returns webhook-ready pipeline payload' do
      conversation = create(
        :conversation,
        account: account,
        conversation_pipeline: pipeline,
        conversation_pipeline_stage: stage,
        pipeline_stage_entered_at: Time.current
      )

      expect(conversation.pipeline_push_data).to include(
        id: pipeline.id,
        name: pipeline.name,
        internal_name: pipeline.internal_name,
        stage: stage.push_event_data
      )
    end
  end
end
