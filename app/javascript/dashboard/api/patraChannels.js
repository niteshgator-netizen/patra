/* global axios */
import ApiClient from './ApiClient';

// Thin wrapper around the Patra::ChannelsController endpoints from Phase H.3.
// Used by the sidebar to fetch live/idle status per inbox and by the connect
// flow to kick off Zernio's headless OAuth for a chosen platform.
class PatraChannelsAPI extends ApiClient {
  constructor() {
    super('patra/channels', { accountScoped: true });
  }

  // POST /channels/connect  body: { platform, redirect_url? }
  // Returns { auth_url, state, zernio_profile_id } — frontend redirects
  // window.location to auth_url.
  connect(platform, redirectUrl = undefined) {
    return axios.post(`${this.url}/connect`, {
      platform,
      redirect_url: redirectUrl,
    });
  }

  // POST /channels/complete  body: { platform, zernio_account_id, page_name, page_username? }
  complete(params) {
    return axios.post(`${this.url}/complete`, params);
  }

  // POST /channels/:id/resync
  resync(inboxId) {
    return axios.post(`${this.url}/${inboxId}/resync`);
  }
}

export default new PatraChannelsAPI();
