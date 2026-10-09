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

  getModels(provider, refresh = false) {
    return axios.get(`${this.url}/credentials/models`, {
      params: { provider, refresh },
    });
  }

  getLogs(assistantId, options = {}) {
    return axios.get(`${this.url}/logs`, {
      ...options,
      params: { assistant_id: assistantId },
    });
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

  getEffectivePrompt(id) {
    return axios.get(`${this.url}/assistants/${id}/prompt`);
  }

  getNotificationOptions() {
    return axios.get(`${this.url}/assistants/notification_options`);
  }

  testNotification(id, conversationId) {
    return axios.post(`${this.url}/assistants/${id}/test_notification`, {
      conversation_id: conversationId,
    });
  }

  getAlerts(assistantId, conversationId, options = {}) {
    return axios.get(`${this.url}/alerts`, {
      ...options,
      params: { assistant_id: assistantId, conversation_id: conversationId },
    });
  }

  resolveAlert(id) {
    return axios.put(`${this.url}/alerts/${id}`);
  }

  getMemory(conversationId) {
    return axios.get(`${this.url}/conversations/${conversationId}/memory`);
  }

  updateMemory(conversationId, memory) {
    return axios.put(`${this.url}/conversations/${conversationId}/memory`, {
      memory,
    });
  }

  rebuildMemory(conversationId) {
    return axios.post(`${this.url}/conversations/${conversationId}/memory`);
  }

  linkMemory(conversationId, sourceId) {
    return axios.post(
      `${this.url}/conversations/${conversationId}/memory/link`,
      { memory: { conversation_id: sourceId } }
    );
  }

  unlinkMemory(conversationId) {
    return axios.delete(
      `${this.url}/conversations/${conversationId}/memory/unlink`
    );
  }

  getAssistantCoverage(assistantId, page = 1, options = {}) {
    return axios.get(`${this.url}/assistants/${assistantId}/coverage`, {
      ...options,
      params: { page },
    });
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

  generateDraft(conversationId, draft, options = {}) {
    return axios.post(
      `${this.url}/conversations/${conversationId}/draft`,
      { draft },
      options
    );
  }

  getConversationState(conversationId) {
    return axios.get(`${this.url}/conversations/${conversationId}/state`);
  }

  updateConversationState(conversationId, data) {
    return axios.put(`${this.url}/conversations/${conversationId}/state`, {
      state: data,
    });
  }

  getConversationAnalysis(conversationId, options = {}) {
    return axios.get(
      `${this.url}/conversations/${conversationId}/analysis`,
      options
    );
  }

  analyzeConversation(conversationId, assistantId, messagesLimit = null) {
    return axios.post(`${this.url}/conversations/${conversationId}/analysis`, {
      analysis: { assistant_id: assistantId, messages_limit: messagesLimit },
    });
  }

  sendConversationAnalysis(conversationId, id, messages) {
    return axios.post(
      `${this.url}/conversations/${conversationId}/analysis/send_reply`,
      {
        analysis: { id, messages },
      }
    );
  }

  createGoogleAuthorization() {
    return axios.post(`${this.url}/google/authorizations`);
  }
}

export default new MarcosxAiAPI();
