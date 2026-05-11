/* global axios */

import ApiClient from './ApiClient';

class Agents extends ApiClient {
  constructor() {
    super('agents', { accountScoped: true });
  }

  bulkInvite({ emails }) {
    return axios.post(`${this.url}/bulk_create`, {
      emails,
    });
  }

  setPassword(id, password) {
    return axios.post(`${this.url}/${id}/set_password`, { password });
  }
}

export default new Agents();
