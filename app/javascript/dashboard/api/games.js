/* global axios */
import ApiClient from './ApiClient';

class GamesAPI extends ApiClient {
  constructor() {
    super('agent_games', { accountScoped: true });
  }

  availableGames() {
    return axios.get(`${this.url}/available_games`);
  }

  activate({ gameId, credentials, displayName, notes, ipWhitelistConfirmed, status }) {
    return axios.post(this.url, {
      game_id: gameId,
      credentials,
      display_name: displayName,
      notes,
      ip_whitelist_confirmed: ipWhitelistConfirmed,
      status: status || 'active',
    });
  }

  updateAgentGame(id, payload) {
    return axios.patch(`${this.url}/${id}`, payload);
  }

  remove(id) {
    return axios.delete(`${this.url}/${id}`);
  }

  testConnection(id) {
    return axios.post(`${this.url}/${id}/test_connection`);
  }
}

export default new GamesAPI();
