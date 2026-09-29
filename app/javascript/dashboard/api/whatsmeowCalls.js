/* global axios */

import ApiClient from './ApiClient';

class WhatsmeowCallsAPI extends ApiClient {
  constructor() {
    super('conversations', { accountScoped: true });
  }

  createSession(conversationId) {
    return axios.post(`${this.url}/${conversationId}/whatsmeow_call_session`);
  }

  getAll() {
    return axios.get(`${this.baseUrl()}/whatsmeow/calls`);
  }

  createLink(inboxId, video) {
    return axios.post(`${this.baseUrl()}/whatsmeow/calls/create_link`, {
      inbox_id: inboxId,
      video,
    });
  }

  dial(inboxId, phoneNumber) {
    return axios.post(`${this.baseUrl()}/whatsmeow/calls/dial`, {
      inbox_id: inboxId,
      phone_number: phoneNumber,
    });
  }
}

export default new WhatsmeowCallsAPI();
