/* global axios */
import ApiClient from './ApiClient';

// Patra Team & Roles endpoints (account-scoped, under /patra). Wires the seat counter, the
// leaderboard, and admin session management built in the A3/SEC backend work.
class PatraTeamAPI extends ApiClient {
  constructor() {
    super('patra', { accountScoped: true });
  }

  // A3 — { used, cap, remaining }
  seats() {
    return axios.get(`${this.url}/seats`);
  }

  // SEC — read-only agent leaderboard
  leaderboard(period) {
    return axios.get(`${this.url}/leaderboard`, { params: { period } });
  }

  // SEC — list a member's active sessions
  sessions(userId) {
    return axios.get(`${this.url}/users/${userId}/sessions`);
  }

  // SEC — force-logout (admin only)
  forceLogout(userId) {
    return axios.delete(`${this.url}/users/${userId}/sessions`);
  }

  // CAP-SETTER — owner/admin sets the member cap; persists to account.settings via patra/settings.
  setMemberCap(cap) {
    return axios.patch(`${this.url}/settings`, { member_cap: cap });
  }
}

export default new PatraTeamAPI();
