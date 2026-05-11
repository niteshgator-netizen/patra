/* global axios */
import ApiClient from './ApiClient';

class OwnerStatsApi extends ApiClient {
  constructor() {
    super('owner_stats', { accountScoped: true, apiVersion: 'v1' });
  }

  show() {
    return axios.get(this.url);
  }
}

export default new OwnerStatsApi();
