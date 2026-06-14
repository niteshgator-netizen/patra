/* global axios */
import ApiClient from './ApiClient';

// Patra (A2) — per-membership "granted main features" (owner-only, enforced server-side).
// id = the AccountUser id. GET returns { granted_main_features: [...] }; PUT replaces it.
class MainFeatureGrantsAPI extends ApiClient {
  constructor() {
    super('main_feature_grants', { accountScoped: true });
  }

  show(accountUserId) {
    return axios.get(`${this.url}/${accountUserId}`);
  }

  update(accountUserId, features) {
    return axios.put(`${this.url}/${accountUserId}`, {
      granted_main_features: features,
    });
  }
}

export default new MainFeatureGrantsAPI();
