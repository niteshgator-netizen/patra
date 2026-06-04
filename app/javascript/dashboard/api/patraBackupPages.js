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
}

export default new PatraBackupPagesAPI();
