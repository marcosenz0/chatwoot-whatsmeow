# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Conversation Pipeline API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account) }
  let(:pipeline) { create(:conversation_pipeline, account: account) }
  let(:stage) { create(:conversation_pipeline_stage, conversation_pipeline: pipeline) }

  before do
    create(:inbox_member, inbox: conversation.inbox, user: agent)
  end

  describe 'POST /api/v1/accounts/:account_id/conversations/:id/pipeline' do
    it 'moves a conversation to a pipeline stage' do
      post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/pipeline",
           params: { pipeline_stage_id: stage.id },
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:success)
      expect(conversation.reload.conversation_pipeline).to eq(pipeline)
      expect(conversation.conversation_pipeline_stage).to eq(stage)
      expect(response.parsed_body['pipeline']['stage']['id']).to eq(stage.id)
    end
  end

  describe 'DELETE /api/v1/accounts/:account_id/conversations/:id/pipeline' do
    it 'removes a conversation from its pipeline stage' do
      conversation.update!(
        conversation_pipeline: pipeline,
        conversation_pipeline_stage: stage,
        pipeline_stage_entered_at: Time.current
      )

      delete "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/pipeline",
             headers: agent.create_new_auth_token,
             as: :json

      expect(response).to have_http_status(:success)
      expect(conversation.reload.conversation_pipeline).to be_nil
      expect(conversation.conversation_pipeline_stage).to be_nil
      expect(conversation.pipeline_stage_entered_at).to be_nil
      expect(response.parsed_body['pipeline']).to be_nil
    end
  end
end
