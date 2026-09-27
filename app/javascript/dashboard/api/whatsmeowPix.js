/* global axios */

import ApiClient from './ApiClient';

class WhatsmeowPixAPI extends ApiClient {
  constructor() {
    super('inboxes', { accountScoped: true });
  }

  getConfiguration(inboxId, conversationId) {
    return axios.get(`${this.url}/${inboxId}/whatsmeow_pix`, {
      params: { conversation_id: conversationId },
    });
  }

  saveConfiguration(inboxId, payload) {
    return axios.patch(`${this.url}/${inboxId}/whatsmeow_pix`, payload);
  }

  deleteConfiguration(inboxId) {
    return axios.delete(`${this.url}/${inboxId}/whatsmeow_pix`);
  }

  send(conversationId, payload = {}) {
    return axios.post(
      `${this.baseUrl()}/conversations/${conversationId}/messages/pix`,
      payload
    );
  }
}

export default new WhatsmeowPixAPI();
