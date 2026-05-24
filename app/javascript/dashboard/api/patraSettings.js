/* global axios */
import ApiClient from './ApiClient';

class PatraSettingsAPI extends ApiClient {
  constructor() {
    super('patra/settings', { accountScoped: true });
  }

  update(data) {
    return axios.patch(this.url, data);
  }
}

export default new PatraSettingsAPI();
