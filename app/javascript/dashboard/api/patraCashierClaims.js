/* global axios */
import ApiClient from './ApiClient';

class PatraCashierClaimsAPI extends ApiClient {
  constructor() {
    super('cashier_claims', { accountScoped: true });
  }

  list() {
    return axios.get(this.url);
  }

  claim(id) {
    return axios.post(`${this.url}/${id}/claim`);
  }

  complete(id) {
    return axios.post(`${this.url}/${id}/complete`);
  }
}

export default new PatraCashierClaimsAPI();
