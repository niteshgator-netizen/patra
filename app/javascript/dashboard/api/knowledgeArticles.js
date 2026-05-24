/* global axios */
import ApiClient from './ApiClient';

class KnowledgeArticlesAPI extends ApiClient {
  constructor() {
    super('knowledge_articles', { accountScoped: true });
  }

  search(q) {
    return axios.get(`${this.url}/search`, { params: { q } });
  }

  draftFromConversations(id) {
    return axios.post(`${this.url}/${id}/draft_from_conversations`);
  }

  improve(id) {
    return axios.post(`${this.url}/${id}/improve`);
  }
}

export default new KnowledgeArticlesAPI();
