/* global axios */
import ApiClient from './ApiClient';

class PatraAiAPI extends ApiClient {
  constructor() {
    super('patra/ai', { accountScoped: true });
  }

  copilotSuggestion(conversationId, draft) {
    return axios.post(`${this.url}/copilot_suggestion`, { conversation_id: conversationId, draft });
  }

  summarize(conversationId) {
    return axios.post(`${this.url}/summarize`, { conversation_id: conversationId });
  }

  suggestTags(conversationId) {
    return axios.post(`${this.url}/suggest_tags`, { conversation_id: conversationId });
  }

  smartCompose(conversationId, prefix) {
    return axios.post(`${this.url}/smart_compose`, { conversation_id: conversationId, prefix });
  }

  translate(text, targetLanguage) {
    return axios.post(`${this.url}/translate`, { text, target_language: targetLanguage });
  }
}

export default new PatraAiAPI();
