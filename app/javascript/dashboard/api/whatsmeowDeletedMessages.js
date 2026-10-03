/* global axios */
import ApiClient from './ApiClient';

class WhatsmeowDeletedMessagesAPI extends ApiClient {
  constructor() {
    super('whatsmeow_deleted_messages', { accountScoped: true });
  }

  get(params, config = {}) {
    return axios.get(this.url, { ...config, params });
  }
}
export default new WhatsmeowDeletedMessagesAPI();
