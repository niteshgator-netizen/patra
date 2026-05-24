/* global axios */
import ApiClient from './ApiClient';

class PlayerBonusesAPI extends ApiClient {
  constructor() {
    super('player_bonuses', { accountScoped: true });
  }

  forContact(contactId) {
    return axios.get(this.url, { params: { contact_id: contactId } });
  }
}

export default new PlayerBonusesAPI();
