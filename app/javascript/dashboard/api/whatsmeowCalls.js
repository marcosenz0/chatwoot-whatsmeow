/* global axios */

import ApiClient from './ApiClient';

class WhatsmeowCallsAPI extends ApiClient {
  constructor() {
    super('conversations', { accountScoped: true });
  }

  createSession(conversationId) {
    return axios.post(`${this.url}/${conversationId}/whatsmeow_call_session`);
  }
}

export default new WhatsmeowCallsAPI();
