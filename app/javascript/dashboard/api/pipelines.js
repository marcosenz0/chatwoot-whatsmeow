/* global axios */
import ApiClient from './ApiClient';

class PipelinesAPI extends ApiClient {
  constructor() {
    super('pipelines', { accountScoped: true });
  }

  board(id, params = {}) {
    return axios.get(`${this.url}/${id}/board`, { params });
  }

  createStage(pipelineId, data) {
    return axios.post(`${this.url}/${pipelineId}/stages`, data);
  }

  updateStage(pipelineId, stageId, data) {
    return axios.patch(`${this.url}/${pipelineId}/stages/${stageId}`, data);
  }

  deleteStage(pipelineId, stageId) {
    return axios.delete(`${this.url}/${pipelineId}/stages/${stageId}`);
  }

  moveConversation({ conversationId, pipelineStageId }) {
    return axios.post(
      `${this.baseUrl()}/conversations/${conversationId}/pipeline`,
      {
        pipeline_stage_id: pipelineStageId,
      }
    );
  }
}

export default new PipelinesAPI();
