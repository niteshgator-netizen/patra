/* global axios */
import CacheEnabledApiClient from './CacheEnabledApiClient';

class PaymentHandlesAPI extends CacheEnabledApiClient {
  constructor() {
    super('payment_handles', { accountScoped: true });
  }

  // eslint-disable-next-line class-methods-use-this
  get cacheModelName() {
    return 'payment_handle';
  }

  ledger(id) {
    return axios.get(`${this.url}/${id}/ledger`);
  }
}

export default new PaymentHandlesAPI();
