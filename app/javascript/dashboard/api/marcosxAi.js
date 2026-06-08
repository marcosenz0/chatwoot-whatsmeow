/* global axios */
import ApiClient from './ApiClient';

class MarcosxAiAPI extends ApiClient {
  constructor() {
    super('marcosx_ai', { accountScoped: true });
  }

  getPreferences() {
    return axios.get(`${this.url}/preferences`);
  }

  updatePreferences(data) {
    return axios.put(`${this.url}/preferences`, data);
  }

  getCredentials() {
    return axios.get(`${this.url}/credentials`);
  }

  saveCredential(id, data) {
    if (id) {
      return axios.put(`${this.url}/credentials/${id}`, data);
    }

    return axios.post(`${this.url}/credentials`, data);
  }

  deleteCredential(id) {
    return axios.delete(`${this.url}/credentials/${id}`);
  }

  testCredential(provider) {
    return axios.post(`${this.url}/credentials/test`, { provider });
  }

  getAssistants() {
    return axios.get(`${this.url}/assistants`);
  }

  createAssistant(data) {
    return axios.post(`${this.url}/assistants`, data);
  }

  updateAssistant(id, data) {
    return axios.put(`${this.url}/assistants/${id}`, data);
  }

  deleteAssistant(id) {
    return axios.delete(`${this.url}/assistants/${id}`);
  }

  getAssistantInboxes(assistantId) {
    return axios.get(`${this.url}/assistants/${assistantId}/inboxes`);
  }

  linkAssistantInbox(assistantId, inboxId) {
    return axios.post(`${this.url}/assistants/${assistantId}/inboxes`, {
      inbox_id: inboxId,
    });
  }

  unlinkAssistantInbox(assistantId, inboxId) {
    return axios.delete(
      `${this.url}/assistants/${assistantId}/inboxes/${inboxId}`
    );
  }

  runPlayground(assistantId, data) {
    return axios.post(`${this.url}/assistants/${assistantId}/playground`, data);
  }

  getConversationState(conversationId) {
    return axios.get(`${this.url}/conversations/${conversationId}/state`);
  }

  updateConversationState(conversationId, data) {
    return axios.put(`${this.url}/conversations/${conversationId}/state`, data);
  }

  createGoogleAuthorization() {
    return axios.post(`${this.url}/google/authorizations`);
  }
}

export default new MarcosxAiAPI();
