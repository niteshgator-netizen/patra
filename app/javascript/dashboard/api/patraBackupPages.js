/* global axios */
import ApiClient from './ApiClient';

class PatraBackupPagesAPI extends ApiClient {
  constructor() {
    super('backup_pages', { accountScoped: true });
  }

  list() {
    return axios.get(this.url);
  }

  create(data) {
    return axios.post(this.url, data);
  }

  update(id, data) {
    return axios.patch(`${this.url}/${id}`, data);
  }

  destroy(id) {
    return axios.delete(`${this.url}/${id}`);
  }

  // B-COVERAGE — read coverage stats (pct fully connected, breakdown, per-page counts, next drip).
  coverage() {
    return axios.get(`${this.url}/coverage`);
  }

  // B-DRIP — owner/manager config (backup_invite_message, backup_drip_enabled, backup_drip_cadence_days).
  // Response also carries drip_master_enabled (the ops-level kill switch, read-only here).
  dripConfig(data) {
    return axios.patch(`${this.url}/drip_config`, data);
  }
}

export default new PatraBackupPagesAPI();
