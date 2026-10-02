/* global axios */
import ApiClient from './ApiClient';

class WhatsmeowConversationsAPI extends ApiClient {
  constructor() {
    super('whatsmeow_conversations', { accountScoped: true });
  }

  readAll(inboxId) {
    return axios.post(`${this.url}/read_all`, { inbox_id: inboxId });
  }
}
export default new WhatsmeowConversationsAPI();
