# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Conversation Pipeline Stages API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:pipeline) { create(:conversation_pipeline, account: account) }

  describe 'POST /api/v1/accounts/:account_id/pipelines/:pipeline_id/stages' do
    it 'creates a stage' do
      post "/api/v1/accounts/#{account.id}/pipelines/#{pipeline.id}/stages",
           params: { stage: { name: 'Follow-up quente', category: 'open', probability: 70 } },
           headers: admin.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['name']).to eq('Follow-up quente')
      expect(response.parsed_body['probability']).to eq(70)
    end
  end

  describe 'PATCH /api/v1/accounts/:account_id/pipelines/:pipeline_id/stages/:id' do
    it 'updates a stage' do
      stage = create(:conversation_pipeline_stage, conversation_pipeline: pipeline)

      patch "/api/v1/accounts/#{account.id}/pipelines/#{pipeline.id}/stages/#{stage.id}",
            params: { stage: { name: 'Qualificado Meta', probability: 60 } },
            headers: admin.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:success)
      expect(stage.reload.name).to eq('Qualificado Meta')
      expect(stage.probability).to eq(60)
    end
  end

  describe 'DELETE /api/v1/accounts/:account_id/pipelines/:pipeline_id/stages/:id' do
    it 'archives a stage and moves conversations to the next active stage' do
      stage = create(:conversation_pipeline_stage, conversation_pipeline: pipeline, position: 0)
      next_stage = create(:conversation_pipeline_stage, conversation_pipeline: pipeline, position: 1)
      conversation = create(
        :conversation,
        account: account,
        conversation_pipeline: pipeline,
        conversation_pipeline_stage: stage,
        pipeline_stage_entered_at: 2.days.ago
      )

      delete "/api/v1/accounts/#{account.id}/pipelines/#{pipeline.id}/stages/#{stage.id}",
             headers: admin.create_new_auth_token,
             as: :json

      expect(response).to have_http_status(:ok)
      expect(stage.reload).to be_archived
      expect(conversation.reload.conversation_pipeline_stage).to eq(next_stage)
      expect(conversation.pipeline_stage_entered_at).to be > 1.minute.ago
    end
  end
end
