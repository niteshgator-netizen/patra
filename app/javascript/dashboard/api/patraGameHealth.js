import ApiClient from './ApiClient';

class PatraGameHealthAPI extends ApiClient {
  constructor() {
    super('patra/game_health', { accountScoped: true });
  }
}

export default new PatraGameHealthAPI();
