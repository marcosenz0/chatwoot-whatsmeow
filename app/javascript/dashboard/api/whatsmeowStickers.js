/* global axios */

import ApiClient from './ApiClient';

class WhatsmeowStickersAPI extends ApiClient {
  constructor() {
    super('whatsmeow/stickers', { accountScoped: true });
  }

  save(attachmentId) {
    return axios.post(this.url, { attachment_id: attachmentId });
  }

  send(id, conversationId, conversationContextId = conversationId) {
    return axios.post(`${this.url}/${id}/send`, {
      conversation_id: conversationId,
      conversation_context_id: conversationContextId,
    });
  }
}

export default new WhatsmeowStickersAPI();
