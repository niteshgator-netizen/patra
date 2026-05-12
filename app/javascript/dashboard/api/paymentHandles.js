/* global axios */

import ApiClient from './ApiClient';

class PaymentHandlesAPI extends ApiClient {
  constructor() {
    super('payment_handles', { accountScoped: true });
  }

  list() {
    return this.get();
  }

  enable(id) {
    return axios.post(`${this.url}/${id}/enable`, {});
  }

  disable(id) {
    return axios.post(`${this.url}/${id}/disable`, {});
  }

  resetFailures(id) {
    return axios.post(`${this.url}/${id}/reset_failures`, {});
  }
}

export default new PaymentHandlesAPI();
