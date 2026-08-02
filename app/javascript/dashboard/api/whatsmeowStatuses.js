/* global axios */

import ApiClient from './ApiClient';

class WhatsmeowStatusesAPI extends ApiClient {
  constructor() {
    super('whatsmeow/statuses', { accountScoped: true });
  }

  getAll(inboxId) {
    return axios.get(this.url, { params: { inbox_id: inboxId } });
  }

  getActivity() {
    return axios.get(`${this.url}/activity`);
  }

  publish(formData) {
    return axios.post(this.url, formData);
  }

  sync(inboxIds) {
    return axios.post(`${this.url}/sync`, { inbox_ids: inboxIds });
  }

  retry(id) {
    return axios.post(`${this.url}/${id}/retry`);
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

  remove(id) {
    return axios.delete(`${this.url}/${id}`);
  }
}

export default new WhatsmeowStatusesAPI();
