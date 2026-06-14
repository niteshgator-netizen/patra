/* global axios */
import ApiClient from './ApiClient';

// Wrapper for the Patra Facebook-connect endpoints (token exchange + multi-page
// reconcile) used by the Channels screen's "Manage Pages" flow. Distinct from
// patraChannels — these live directly under the patra namespace, not under
// patra/channels.
class PatraFacebookConnectAPI extends ApiClient {
  constructor() {
    super('patra', { accountScoped: true });
  }

  // POST /patra/fb_connect — exchange the short-lived FB.login user token.
  // Returns { pages: [{ id, name, access_token }], user_access_token,
  //           facebook_identity_id, already_connected_fb_page_ids }.
  fbConnect(accessToken) {
    return axios.post(`${this.url}/fb_connect`, { access_token: accessToken });
  }

  // POST /patra/sync_pages — reconcile the desired page set: creates inboxes for
  // newly-chosen pages and soft-disconnects de-selected ones (keeps history).
  syncPages(payload) {
    return axios.post(`${this.url}/sync_pages`, payload);
  }
}

export default new PatraFacebookConnectAPI();
