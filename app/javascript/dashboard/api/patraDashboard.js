import ApiClient from './ApiClient';

class PatraDashboardAPI extends ApiClient {
  constructor() {
    super('patra/dashboard', { accountScoped: true });
  }
}

export default new PatraDashboardAPI();
