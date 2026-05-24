/* global axios */
import ApiClient from './ApiClient';

class ContactBlacklistAPI extends ApiClient {
  constructor() {
    super('contacts', { accountScoped: true });
  }

  update(contactId, payload) {
    return axios.patch(`${this.url}/${contactId}/blacklist`, payload);
  }
}

export default new ContactBlacklistAPI();
