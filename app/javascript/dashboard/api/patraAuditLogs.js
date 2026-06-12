/* global axios */
import ApiClient from './ApiClient';

class PatraAuditLogsAPI extends ApiClient {
  constructor() {
    super('patra_audit_logs', { accountScoped: true });
  }

  list() {
    return axios.get(this.url);
  }
}

export default new PatraAuditLogsAPI();
