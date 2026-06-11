/* global axios */
import ApiClient from './ApiClient';

class PatraAiAPI extends ApiClient {
  constructor() {
    super('patra/ai', { accountScoped: true });
  }

  copilotSuggestion(conversationId, draft) {
    return axios.post(`${this.url}/copilot_suggestion`, {
      conversation_id: conversationId,
      draft,
    });
  }

  summarize(conversationId) {
    return axios.post(`${this.url}/summarize`, {
      conversation_id: conversationId,
    });
  }

  suggestTags(conversationId) {
    return axios.post(`${this.url}/suggest_tags`, {
      conversation_id: conversationId,
    });
  }

  smartCompose(conversationId, prefix) {
    return axios.post(`${this.url}/smart_compose`, {
      conversation_id: conversationId,
      prefix,
    });
  }

  translate(text, targetLanguage) {
    return axios.post(`${this.url}/translate`, {
      text,
      target_language: targetLanguage,
    });
  }

  // HB-1: on-demand conversation analysis. conversationId is the display_id
  // (frontend conversation.id IS the display_id). Returns { analysis: {...} };
  // 422 unparseable model output, 503 model unavailable.
  analyzeConversation(conversationId) {
    return axios.post(
      `${this.baseUrl()}/conversations/${conversationId}/patra_ai_analysis`
    );
  }

  // HB-2: persona playground — no persistence, no sends.
  // Returns { reply, prompt }; 422 blank message, 503 model unavailable.
  playgroundMessage(message, context) {
    return axios.post(`${this.baseUrl()}/patra_playground/messages`, {
      message,
      context,
    });
  }
}

export default new PatraAiAPI();
