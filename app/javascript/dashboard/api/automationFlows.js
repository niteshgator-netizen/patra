/* global axios */
import ApiClient from './ApiClient';

class AutomationFlowsAPI extends ApiClient {
  constructor() {
    super('automation_flows', { accountScoped: true });
  }

  duplicate(id) {
    return axios.post(`${this.url}/${id}/duplicate`);
  }

  preview(id, params) {
    return axios.post(`${this.url}/${id}/preview`, params);
  }

  activate(id) {
    return axios.post(`${this.url}/${id}/activate`);
  }

  analytics(id) {
    return axios.get(`${this.url}/${id}/analytics`);
  }

  templates() {
    return axios.get(`${this.url}/templates`);
  }

  fromTemplate(templateKey) {
    return axios.post(`${this.url}/from_template`, { template_key: templateKey });
  }
}

export default new AutomationFlowsAPI();
