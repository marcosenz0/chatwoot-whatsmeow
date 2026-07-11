/* global axios */

import ApiClient from './ApiClient';

class WhatsmeowStatusesAPI extends ApiClient {
  constructor() {
    super('whatsmeow/statuses', { accountScoped: true });
  }

  getAll(inboxId) {
    return axios.get(this.url, { params: { inbox_id: inboxId } });
  }

  publish(formData) {
    return axios.post(this.url, formData);
  }

  markViewed(id) {
    return axios.post(`${this.url}/${id}/view`);
  }

  reply(id, payload) {
    return axios.post(`${this.url}/${id}/reply`, payload);
  }

  getViewers(id) {
    return axios.get(`${this.url}/${id}/viewers`);
  }

  preview(id) {
    return axios.get(`${this.url}/${id}/preview`);
  }
}

export default new WhatsmeowStatusesAPI();
