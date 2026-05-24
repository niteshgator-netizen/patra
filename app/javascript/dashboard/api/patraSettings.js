import ApiClient from './ApiClient';

class PatraSettingsAPI extends ApiClient {
  constructor() {
    super('patra/settings', { accountScoped: true });
  }
}

export default new PatraSettingsAPI();
