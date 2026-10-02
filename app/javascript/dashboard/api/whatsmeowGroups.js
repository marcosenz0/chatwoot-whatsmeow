/* global axios */
import ApiClient from './ApiClient';

class WhatsmeowGroupsAPI extends ApiClient {
  constructor() {
    super('inboxes', { accountScoped: true });
  }

  path(inboxId) {
    return `${this.url}/${inboxId}/whatsmeow_group`;
  }

  show(inboxId, groupJid, config = {}) {
    return axios.get(this.path(inboxId), {
      ...config,
      params: { group_jid: groupJid },
    });
  }

  create(inboxId, data) {
    return axios.post(this.path(inboxId), data);
  }

  update(inboxId, data) {
    return axios.patch(this.path(inboxId), data);
  }

  action(inboxId, data) {
    return axios.post(`${this.path(inboxId)}/action`, data);
  }

  contacts(inboxId, params, config = {}) {
    return axios.get(`${this.path(inboxId)}/contacts`, { ...config, params });
  }

  requests(inboxId, groupJid) {
    return axios.get(`${this.path(inboxId)}/requests`, {
      params: { group_jid: groupJid },
    });
  }
}
export default new WhatsmeowGroupsAPI();
