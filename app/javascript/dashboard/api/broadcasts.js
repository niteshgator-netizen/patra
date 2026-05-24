/* global axios */
import ApiClient from './ApiClient';

class BroadcastsAPI extends ApiClient {
  constructor() {
    super('broadcasts', { accountScoped: true });
  }

  sendNow(id) {
    return axios.post(`${this.url}/${id}/send_now`);
  }

  previewCount(id) {
    return axios.get(`${this.url}/${id}/preview_count`);
  }
}

export default new BroadcastsAPI();
