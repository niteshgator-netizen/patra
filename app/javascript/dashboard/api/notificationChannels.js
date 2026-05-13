/* global axios */
import ApiClient from './ApiClient';

class NotificationChannelsAPI extends ApiClient {
  constructor() {
    super('notification_channels', { accountScoped: true });
  }

  testConnection(id) {
    return axios.post(`${this.url}/${id}/test_connection`);
  }
}

export default new NotificationChannelsAPI();
