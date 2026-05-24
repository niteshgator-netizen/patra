import ApiClient from './ApiClient';

class PatraReportsAPI extends ApiClient {
  constructor() {
    super('patra/reports', { accountScoped: true });
  }
}

export default new PatraReportsAPI();
