/* global axios */
import ApiClient from './ApiClient';

class CashierClaimsAPI extends ApiClient {
  constructor() {
    super('cashier_claims', { accountScoped: true });
  }

  claim(id) {
    return axios.post(`${this.url}/${id}/claim`);
  }

  complete(id) {
    return axios.post(`${this.url}/${id}/complete`);
  }
}

export default new CashierClaimsAPI();
