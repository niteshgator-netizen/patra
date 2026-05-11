/* global axios */
import ApiClient from './ApiClient';

class OwnerStatsApi extends ApiClient {
  constructor() {
    super('owner_stats', { accountScoped: true, apiVersion: 'v1' });
  }

  show(accountId = null) {
    const id = accountId ?? this.accountIdFromRoute;
    const base = `${this.apiVersion}/accounts/${id}`;
    return axios.get(`${base}/owner_stats`);
  }
}

export default new OwnerStatsApi();
