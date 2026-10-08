/* global axios */
import ApiClient from './ApiClient';

class WhatsappProfile extends ApiClient {
  constructor() {
    super('inboxes', { accountScoped: true });
  }

  show(inboxId) {
    return axios.get(`${this.url}/${inboxId}/whatsmeow_profile`);
  }

  update(inboxId, data) {
    return axios.patch(`${this.url}/${inboxId}/whatsmeow_profile`, data);
  }

  photo(inboxId) {
    return axios.get(`${this.url}/${inboxId}/whatsmeow_profile/photo`);
  }

  updatePhoto(inboxId, photo) {
    return axios.put(`${this.url}/${inboxId}/whatsmeow_profile/photo`, {
      photo,
    });
  }

  removePhoto(inboxId) {
    return axios.delete(`${this.url}/${inboxId}/whatsmeow_profile/photo`);
  }

  contactPhoto(contactId, inboxId) {
    return axios.get(`${this.baseUrl()}/contacts/${contactId}/profile_photo`, {
      params: { inbox_id: inboxId },
    });
  }
}

export default new WhatsappProfile();
