/* global axios */
import ApiClient from './ApiClient';

class PatraAgentFeedbackAPI extends ApiClient {
  constructor() {
    super('patra_agent_feedbacks', { accountScoped: true });
  }

  list(params = {}) {
    return axios.get(this.url, { params });
  }

  create(data) {
    return axios.post(this.url, data);
  }

  setStatus(id, status) {
    return axios.patch(`${this.url}/${id}`, { status });
  }
}

export default new PatraAgentFeedbackAPI();
