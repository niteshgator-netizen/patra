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

  // POST /channels/fb_list_pages  body: { connect_token, temp_token, profile_id }
  // Returns { pages: [{ id, name, username, category, ... }] } — the Facebook
  // pages to choose from after Zernio's headless OAuth returns the browser.
  fbListPages(payload) {
    return axios.post(`${this.url}/fb_list_pages`, payload);
  }

  // POST /channels/fb_connect_pages
  // body: { connect_token, temp_token, profile_id, user_profile, page_ids: [..] }
  // Saves the chosen pages on Zernio and creates the matching inboxes.
  // Returns { saved: [...], inboxes: [{ id, name }] }.
  fbConnectPages(payload) {
    return axios.post(`${this.url}/fb_connect_pages`, payload);
  }

  // POST /channels/:id/resync
  resync(inboxId) {
    return axios.post(`${this.url}/${inboxId}/resync`);
  }

  // POST /channels/:id/disconnect — soft-disconnect; conversation history stays.
  disconnect(inboxId) {
    return axios.post(`${this.url}/${inboxId}/disconnect`);
  }

  // POST /channels/:id/reconnect — returns { reauth_url } to restart OAuth.
  reconnect(inboxId) {
    return axios.post(`${this.url}/${inboxId}/reconnect`);
  }

  // DELETE /channels/:id — destroys the inbox + conversations. The backend
  // refuses unless confirm:true, so we always send it; the UI gates with its own
  // confirmation dialog first.
  destroy(inboxId) {
    return axios.delete(`${this.url}/${inboxId}`, { data: { confirm: true } });
  }
}

export default new PatraChannelsAPI();
