/* global axios */
import ApiClient from './ApiClient';

class PatraConversationsAPI extends ApiClient {
  constructor() {
    super('', { accountScoped: true });
  }

  patraPath(suffix) {
    return `${this.baseUrl()}/patra/${suffix}`;
  }

  togglePin(conversationId) {
    return axios.post(
      this.patraPath(`conversations/${conversationId}/toggle_pin`)
    );
  }

  getSummary(conversationId) {
    return axios.get(
      this.patraPath(`conversations/${conversationId}/summary`)
    );
  }
}

export default new PatraConversationsAPI();
