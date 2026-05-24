/* global axios */
import ApiClient from './ApiClient';

class DripCampaignsAPI extends ApiClient {
  constructor() {
    super('drip_campaigns', { accountScoped: true });
  }

  activate(id) {
    return axios.post(`${this.url}/${id}/activate`);
  }
}

export default new DripCampaignsAPI();
