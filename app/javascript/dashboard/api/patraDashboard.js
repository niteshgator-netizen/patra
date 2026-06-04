/* global axios */
import ApiClient from './ApiClient';

class PatraDashboardAPI extends ApiClient {
  constructor() {
    super('patra/dashboard', { accountScoped: true });
  }

  get(options = {}) {
    return axios.get(this.url, options);
  }
}

export default new PatraDashboardAPI();
