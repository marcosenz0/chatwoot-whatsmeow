/* global axios */
import ApiClient from './ApiClient';

class WhatsmeowStarredMessagesAPI extends ApiClient {
  constructor() {
    super('whatsmeow_starred_messages', { accountScoped: true });
  }

  get(params, config = {}) {
    return axios.get(this.url, { ...config, params });
  }

  sync(inboxId) {
    return axios.post(
      `${this.url}/sync`,
      { inbox_id: inboxId },
      { timeout: 150000 }
    );
  }
}
export default new WhatsmeowStarredMessagesAPI();
