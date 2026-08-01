/* global axios */
/* eslint-disable max-classes-per-file */
import ApiClient from './ApiClient';

class WhatsAppCloudAutomationsAPI extends ApiClient {
  constructor() {
    super('whatsapp_cloud/automations', { accountScoped: true });
  }

  getForInbox(inboxId) {
    return axios.get(this.url, { params: { inbox_id: inboxId } });
  }

  publish(id) {
    return axios.post(`${this.url}/${id}/publish`);
  }

  pause(id) {
    return axios.post(`${this.url}/${id}/pause`);
  }
}

class WhatsAppCloudTemplatesAPI extends ApiClient {
  constructor() {
    super('whatsapp_cloud/templates', { accountScoped: true });
  }

  getForInbox(inboxId, sync = false) {
    return axios.get(this.url, { params: { inbox_id: inboxId, sync } });
  }

  createForInbox(inboxId, template) {
    return axios.post(this.url, { inbox_id: inboxId, template });
  }

  sync(inboxId) {
    return axios.post(`${this.url}/sync`, { inbox_id: inboxId });
  }

  deleteForInbox(inboxId, name) {
    return axios.delete(`${this.url}/destroy`, {
      params: { inbox_id: inboxId, name },
    });
  }
}

class WhatsAppCloudAudienceEstimateAPI extends ApiClient {
  constructor() {
    super('whatsapp_cloud/audience_estimate', { accountScoped: true });
  }

  getEstimate({ inboxId, labelIds, category }) {
    return axios.get(this.url, {
      params: {
        inbox_id: inboxId,
        label_ids: labelIds,
        category,
      },
    });
  }
}

export const whatsappCloudAutomationsAPI = new WhatsAppCloudAutomationsAPI();
export const whatsappCloudTemplatesAPI = new WhatsAppCloudTemplatesAPI();
export const whatsappCloudAudienceEstimateAPI =
  new WhatsAppCloudAudienceEstimateAPI();
