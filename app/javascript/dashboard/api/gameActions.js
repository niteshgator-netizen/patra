/* global axios */
import ApiClient from './ApiClient';

class GameActionsAPI extends ApiClient {
  constructor() {
    super('game_actions', { accountScoped: true });
  }

  forContact(contactId, actionType) {
    return axios.get(this.url, {
      params: { contact_id: contactId, action_type: actionType },
    });
  }
}

export default new GameActionsAPI();
