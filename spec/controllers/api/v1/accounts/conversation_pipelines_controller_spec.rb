# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Conversation Pipelines API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  describe 'GET /api/v1/accounts/:account_id/pipelines' do
    it 'returns unauthorized when unauthenticated' do
      get "/api/v1/accounts/#{account.id}/pipelines"

      expect(response).to have_http_status(:unauthorized)
    end

    it 'seeds and returns the default pipeline for agents' do
      get "/api/v1/accounts/#{account.id}/pipelines",
          headers: agent.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload'].first['name']).to eq('Funil principal')
      expect(response.parsed_body['payload'].first['stages'].size).to eq(7)
    end
  end

  describe 'POST /api/v1/accounts/:account_id/pipelines' do
    it 'creates a custom pipeline with custom stages' do
      post "/api/v1/accounts/#{account.id}/pipelines",
           params: {
             pipeline: { name: 'Lead campanha Meta', color: '#2563eb', default: true },
             stages: [
               { name: 'Novo lead', category: 'open', probability: 10 },
               { name: 'Fechou agenda', category: 'won', probability: 100 }
             ]
           },
           headers: admin.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['name']).to eq('Lead campanha Meta')
      expect(response.parsed_body['internal_name']).to eq('lead_campanha_meta')
      expect(response.parsed_body['stages'].pluck('name')).to eq(['Novo lead', 'Fechou agenda'])
    end
  end

  describe 'GET /api/v1/accounts/:account_id/pipelines/:id/board' do
    let(:pipeline) { create(:conversation_pipeline, account: account) }
    let(:stage) { create(:conversation_pipeline_stage, conversation_pipeline: pipeline) }

    it 'returns a Kanban board payload' do
      create(
        :conversation,
        account: account,
        conversation_pipeline: pipeline,
        conversation_pipeline_stage: stage,
        pipeline_stage_entered_at: Time.current
      )

      get "/api/v1/accounts/#{account.id}/pipelines/#{pipeline.id}/board",
          headers: admin.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
      payload = response.parsed_body['payload']
      expect(payload['pipeline']['id']).to eq(pipeline.id)
      expect(payload['stages'].first['count']).to eq(1)
      expect(payload['total_count']).to eq(1)
    end
  end

  describe 'DELETE /api/v1/accounts/:account_id/pipelines/:id' do
    it 'archives a pipeline and assigns a new default' do
      pipeline = create(:conversation_pipeline, account: account, default: true)
      fallback_pipeline = create(:conversation_pipeline, account: account)

      delete "/api/v1/accounts/#{account.id}/pipelines/#{pipeline.id}",
             headers: admin.create_new_auth_token,
             as: :json

      expect(response).to have_http_status(:ok)
      expect(pipeline.reload).to be_archived
      expect(fallback_pipeline.reload).to be_default
    end
  end
end
