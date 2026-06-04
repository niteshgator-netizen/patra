/* global axios */
import ApiClient from './ApiClient';

class PatraFacebookIdentitiesAPI extends ApiClient {
  constructor() {
    super('patra/facebook_identities', { accountScoped: true });
  }

  list() {
    return axios.get(this.url);
  }

  disconnect(id) {
    return axios.delete(`${this.url}/${id}`);
  }
}

export default new PatraFacebookIdentitiesAPI();
