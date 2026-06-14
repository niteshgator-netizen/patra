<script setup>
import { ref, computed, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import { loadScript } from 'dashboard/helper/DOMHelpers';
import PatraChannelsAPI from 'dashboard/api/patraChannels';
import PatraFacebookIdentitiesAPI from 'dashboard/api/patraFacebookIdentities';
import PatraFacebookConnectAPI from 'dashboard/api/patraFacebookConnect';

const showAlert = useAlert;

const identities = ref([]);
const channels = ref([]);
const loading = ref(true);
const busyInbox = ref(null);
const busyAccount = ref(null);

// Manage Pages modal
const mpOpen = ref(false);
const mpLoading = ref(false);
const mpSaving = ref(false);
const mpIdentity = ref(null);
const mpConnectIdentityId = ref(null);
const mpUserToken = ref('');
const mpPages = ref([]);
const mpSelected = ref(new Set());

const FB_SCOPE =
  'pages_show_list,pages_messaging,pages_manage_metadata,pages_read_engagement,business_management';

onMounted(loadAll);

async function loadAll() {
  loading.value = true;
  try {
    const [idRes, chRes] = await Promise.all([
      PatraFacebookIdentitiesAPI.list(),
      PatraChannelsAPI.get(),
    ]);
    identities.value = idRes.data || [];
    channels.value = chRes?.data?.channels || [];
  } catch {
    showAlert('Failed to load connected channels');
  } finally {
    loading.value = false;
  }
}

const fbInboxIds = computed(() => {
  const ids = new Set();
  identities.value.forEach(idn =>
    (idn.inboxes || []).forEach(i => ids.add(i.id))
  );
  return ids;
});

// Channels that are not Facebook pages (Instagram / WhatsApp / Telegram / …).
// Facebook-platform inboxes belong under their FB account section; excluding
// them by platform also keeps an orphaned bridge inbox (one with no linked
// identity) from showing up here as a mislabeled standalone "Facebook" card.
const otherChannels = computed(() =>
  channels.value.filter(
    c => !fbInboxIds.value.has(c.id) && c.platform !== 'facebook'
  )
);

const isInactive = row =>
  row?.status === 'inactive' || row?.connection_status === 'inactive';

const platformLabel = c => {
  const map = {
    facebook: 'Facebook',
    instagram: 'Instagram',
    whatsapp: 'WhatsApp',
    telegram: 'Telegram',
    tiktok: 'TikTok',
    sms: 'SMS',
    email: 'Email',
    web: 'Web',
  };
  return map[c.platform] || (c.platform ? c.platform : 'Channel');
};

const apiErr = e =>
  e?.response?.data?.error || e?.message || 'unknown error';

async function disconnectInbox(inbox) {
  busyInbox.value = inbox.id;
  try {
    await PatraChannelsAPI.disconnect(inbox.id);
    showAlert(`${inbox.name} disconnected — conversations kept.`);
    await loadAll();
  } catch (e) {
    showAlert(`Disconnect failed: ${apiErr(e)}`);
  } finally {
    busyInbox.value = null;
  }
}

async function reconnectInbox(inbox) {
  busyInbox.value = inbox.id;
  try {
    const res = await PatraChannelsAPI.reconnect(inbox.id);
    const url = res?.data?.reauth_url;
    if (url) {
      window.location.href = url;
      return;
    }
    showAlert('Reconnect started.');
    await loadAll();
  } catch (e) {
    showAlert(`Reconnect failed: ${apiErr(e)}`);
  } finally {
    busyInbox.value = null;
  }
}

async function deleteInbox(inbox) {
  if (
    !window.confirm(
      `Delete ${inbox.name}? This permanently removes the inbox and its conversations and cannot be undone.`
    )
  ) {
    return;
  }
  busyInbox.value = inbox.id;
  try {
    await PatraChannelsAPI.destroy(inbox.id);
    showAlert(`${inbox.name} deleted.`);
    await loadAll();
  } catch (e) {
    showAlert(`Delete failed: ${apiErr(e)}`);
  } finally {
    busyInbox.value = null;
  }
}

async function disconnectAccount(identity) {
  busyAccount.value = identity.id;
  try {
    const results = await Promise.allSettled(
      (identity.inboxes || []).map(i => PatraChannelsAPI.disconnect(i.id))
    );
    const failed = results.filter(r => r.status === 'rejected').length;
    if (failed) {
      showAlert(`${identity.fb_user_name}: ${failed} page(s) could not be disconnected.`);
    } else {
      showAlert(`${identity.fb_user_name} disconnected — pages kept.`);
    }
  } catch (e) {
    showAlert(`Disconnect failed: ${apiErr(e)}`);
  } finally {
    busyAccount.value = null;
    await loadAll();
  }
}

async function deleteAccount(identity) {
  const count = (identity.inboxes || []).length;
  if (
    !window.confirm(
      `Delete the Facebook account ${identity.fb_user_name} and all ${count} of its page inbox(es)? This cannot be undone.`
    )
  ) {
    return;
  }
  busyAccount.value = identity.id;
  try {
    const results = await Promise.allSettled(
      (identity.inboxes || []).map(i => PatraChannelsAPI.destroy(i.id))
    );
    const failed = results.filter(r => r.status === 'rejected').length;
    if (failed === 0) {
      // Only remove the identity once every page is gone — deleting it first
      // would nullify the remaining pages' link and orphan them.
      await PatraFacebookIdentitiesAPI.disconnect(identity.id);
      showAlert(`${identity.fb_user_name} removed.`);
    } else {
      showAlert(`${identity.fb_user_name}: ${failed} page(s) could not be deleted — account kept.`);
    }
  } catch (e) {
    showAlert(`Delete failed: ${apiErr(e)}`);
  } finally {
    busyAccount.value = null;
    await loadAll();
  }
}

// ── Manage Pages: reuse the Facebook OAuth + page-fetch path ─────────────────
async function loadFBsdk() {
  return loadScript('https://connect.facebook.net/en_US/sdk.js', {
    id: 'facebook-jssdk',
  });
}

function runFBInit() {
  window.FB.init({
    appId: window.chatwootConfig.fbAppId,
    xfbml: true,
    version: window.chatwootConfig.fbApiVersion,
    status: true,
  });
}

async function openManagePages(identity) {
  mpIdentity.value = identity;
  mpPages.value = [];
  mpSelected.value = new Set();
  mpUserToken.value = '';
  mpConnectIdentityId.value = null;
  mpSaving.value = false;
  mpOpen.value = true;
  mpLoading.value = true;
  try {
    await loadFBsdk();
    runFBInit();
    window.FB.login(
      response => {
        if (response.status === 'connected') {
          fetchManageablePages(response.authResponse.accessToken);
        } else {
          showAlert('Facebook sign-in was cancelled.');
          closeManagePages();
        }
      },
      { scope: FB_SCOPE }
    );
  } catch {
    showAlert('Could not load the Facebook SDK.');
    closeManagePages();
  }
}

async function fetchManageablePages(token) {
  try {
    const res = await PatraFacebookConnectAPI.fbConnect(token);
    const data = res.data || {};
    mpUserToken.value = data.user_access_token;
    mpConnectIdentityId.value = data.facebook_identity_id;
    mpPages.value = (data.pages || []).map(p => ({
      id: String(p.id || p.fb_page_id || ''),
      name: p.name || `Page ${p.id || ''}`,
      access_token: p.access_token,
    }));
    const connected = new Set(
      (data.already_connected_fb_page_ids || []).map(String)
    );
    mpSelected.value = new Set(
      mpPages.value.filter(p => connected.has(p.id)).map(p => p.id)
    );
  } catch (e) {
    if (e?.response?.status === 403) {
      showAlert(
        "You don't have permission to manage Facebook connections — ask an account owner to grant access."
      );
    } else {
      showAlert(`Could not load your Facebook pages: ${apiErr(e)}`);
    }
    closeManagePages();
  } finally {
    mpLoading.value = false;
  }
}

function togglePage(pageId) {
  const next = new Set(mpSelected.value);
  if (next.has(pageId)) {
    next.delete(pageId);
  } else {
    next.add(pageId);
  }
  mpSelected.value = next;
}

const pageChecked = pageId => mpSelected.value.has(pageId);

async function saveManagePages() {
  mpSaving.value = true;
  try {
    const chosen = mpPages.value.filter(p => mpSelected.value.has(p.id));
    await PatraFacebookConnectAPI.syncPages({
      user_access_token: mpUserToken.value,
      facebook_identity_id: mpConnectIdentityId.value || mpIdentity.value?.id,
      pages: chosen.map(p => ({
        id: p.id,
        name: p.name,
        access_token: p.access_token,
      })),
    });
    showAlert('Pages updated.');
    closeManagePages();
    await loadAll();
  } catch (e) {
    showAlert(`Could not update pages: ${apiErr(e)}`);
  } finally {
    mpSaving.value = false;
  }
}

function closeManagePages() {
  mpOpen.value = false;
  mpLoading.value = false;
  mpSaving.value = false;
}
</script>

<template>
  <div class="pat-channels">
    <header class="pc-head">
      <h1>Connected Channels</h1>
      <p class="pc-sub">
        Manage every connected inbox. Disconnect keeps your conversation history;
        Delete removes the inbox for good.
      </p>
    </header>

    <div v-if="loading" class="pc-empty">Loading channels…</div>

    <template v-else>
      <div
        v-if="identities.length === 0 && otherChannels.length === 0"
        class="pc-empty"
      >
        <div class="pc-empty-ic">🔌</div>
        No channels connected yet.
      </div>

      <!-- Facebook accounts, each with its pages as rows -->
      <section
        v-for="identity in identities"
        :key="'fb-' + identity.id"
        class="pc-card"
      >
        <div class="pc-acct-head">
          <img
            v-if="identity.fb_user_avatar_url"
            :src="identity.fb_user_avatar_url"
            :alt="identity.fb_user_name"
            class="pc-avatar"
            @error="identity.fb_user_avatar_url = ''"
          />
          <div v-else class="pc-avatar pc-avatar--fallback">
            {{ identity.fb_user_name?.[0] || 'F' }}
          </div>

          <div class="pc-acct-info">
            <div class="pc-name">{{ identity.fb_user_name }}</div>
            <div class="pc-meta">
              Facebook · {{ (identity.inboxes || []).length }} page(s)
            </div>
          </div>

          <div class="pc-actions">
            <button
              class="pc-btn pc-btn--primary"
              :disabled="busyAccount === identity.id"
              @click="openManagePages(identity)"
            >
              {{ (identity.inboxes || []).length ? 'Manage Pages' : 'Choose Pages' }}
            </button>
            <button
              class="pc-btn"
              :disabled="busyAccount === identity.id || !(identity.inboxes || []).length"
              @click="disconnectAccount(identity)"
            >
              Disconnect
            </button>
            <button
              class="pc-btn pc-btn--danger"
              :disabled="busyAccount === identity.id"
              @click="deleteAccount(identity)"
            >
              Delete
            </button>
          </div>
        </div>

        <div v-if="(identity.inboxes || []).length" class="pc-pages">
          <div v-for="page in identity.inboxes" :key="page.id" class="pc-row">
            <div class="pc-row-main">
              <span class="pc-row-name">{{ page.name }}</span>
              <span v-if="page.fb_page_id" class="pc-row-id">
                #{{ page.fb_page_id }}
              </span>
            </div>
            <span
              class="pc-badge"
              :class="isInactive(page) ? 'pc-badge--inactive' : 'pc-badge--active'"
            >
              {{ isInactive(page) ? 'Inactive' : 'Active' }}
            </span>
            <div class="pc-actions">
              <button
                v-if="isInactive(page)"
                class="pc-btn pc-btn--reconnect"
                :disabled="busyInbox === page.id"
                @click="reconnectInbox(page)"
              >
                Reconnect
              </button>
              <button
                v-else
                class="pc-btn"
                :disabled="busyInbox === page.id"
                @click="disconnectInbox(page)"
              >
                Disconnect
              </button>
              <button
                class="pc-btn pc-btn--danger"
                :disabled="busyInbox === page.id"
                @click="deleteInbox(page)"
              >
                Delete
              </button>
            </div>
          </div>
        </div>
        <div v-else class="pc-pages-empty">
          No pages connected for this account yet — use Choose Pages above.
        </div>
      </section>

      <!-- Non-Facebook channels (Instagram / WhatsApp / Telegram / …) -->
      <section
        v-for="ch in otherChannels"
        :key="'ch-' + ch.id"
        class="pc-card"
      >
        <div class="pc-row pc-row--solo">
          <div class="pc-row-main">
            <span class="pc-row-name">{{ ch.name }}</span>
            <span class="pc-row-id">{{ platformLabel(ch) }}</span>
          </div>
          <span
            class="pc-badge"
            :class="isInactive(ch) ? 'pc-badge--inactive' : 'pc-badge--active'"
          >
            {{ isInactive(ch) ? 'Inactive' : 'Active' }}
          </span>
          <div class="pc-actions">
            <button
              v-if="isInactive(ch)"
              class="pc-btn pc-btn--reconnect"
              :disabled="busyInbox === ch.id"
              @click="reconnectInbox(ch)"
            >
              Reconnect
            </button>
            <button
              v-else
              class="pc-btn"
              :disabled="busyInbox === ch.id"
              @click="disconnectInbox(ch)"
            >
              Disconnect
            </button>
            <button
              class="pc-btn pc-btn--danger"
              :disabled="busyInbox === ch.id"
              @click="deleteInbox(ch)"
            >
              Delete
            </button>
          </div>
        </div>
      </section>
    </template>

    <!-- Manage Pages modal -->
    <div v-if="mpOpen" class="pc-overlay" @click.self="closeManagePages">
      <div class="pc-modal">
        <div class="pc-modal-head">
          <div>
            <div class="pc-modal-title">Manage Pages</div>
            <div class="pc-modal-sub">
              {{ mpIdentity?.fb_user_name }} · pick the pages to keep connected
            </div>
          </div>
          <button class="pc-modal-x" @click="closeManagePages">✕</button>
        </div>

        <div class="pc-modal-body">
          <div v-if="mpLoading" class="pc-empty">
            Loading your Facebook pages…
          </div>
          <div v-else-if="mpPages.length === 0" class="pc-empty">
            No pages found for this account.
          </div>
          <div v-else>
            <label
              v-for="page in mpPages"
              :key="page.id"
              class="pc-check-row"
            >
              <input
                type="checkbox"
                class="pc-check"
                :checked="pageChecked(page.id)"
                @change="togglePage(page.id)"
              />
              <span class="pc-check-name">{{ page.name }}</span>
              <span class="pc-row-id">#{{ page.id }}</span>
            </label>
            <p class="pc-modal-note">
              Unchecking a connected page disconnects it but keeps its
              conversation history. Checking a new page connects it.
            </p>
          </div>
        </div>

        <div class="pc-modal-foot">
          <button class="pc-btn" @click="closeManagePages">Cancel</button>
          <button
            class="pc-btn pc-btn--primary"
            :disabled="mpSaving || mpLoading"
            @click="saveManagePages"
          >
            {{ mpSaving ? 'Saving…' : 'Save pages' }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.pat-channels {
  max-width: 880px;
  margin: 0 auto;
  padding: 28px 24px 48px;
  font-family: 'Inter', sans-serif;
  color: var(--text);
}

.pc-head {
  margin-bottom: 22px;
}
.pc-head h1 {
  font-family: 'Space Grotesk', 'Inter', sans-serif;
  font-weight: 600;
  font-size: 23px;
  color: var(--text);
}
.pc-sub {
  margin-top: 4px;
  font-size: 13px;
  color: var(--text-3);
  max-width: 62ch;
}

.pc-card {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 16px;
  padding: 18px;
  margin-bottom: 16px;
  transition: border-color 0.2s ease, box-shadow 0.2s ease;
}
.pc-card:hover {
  border-color: var(--patra);
  box-shadow: var(--shadow);
}

.pc-acct-head {
  display: flex;
  align-items: center;
  gap: 13px;
}
.pc-avatar {
  width: 40px;
  height: 40px;
  border-radius: 50%;
  flex-shrink: 0;
  object-fit: cover;
  border: 1px solid var(--border-hi);
}
.pc-avatar--fallback {
  display: flex;
  align-items: center;
  justify-content: center;
  background: var(--patra);
  color: white;
  font-weight: 700;
  font-family: 'Space Grotesk', sans-serif;
}
.pc-acct-info {
  flex: 1;
  min-width: 0;
}
.pc-name {
  font-family: 'Space Grotesk', 'Inter', sans-serif;
  font-weight: 600;
  font-size: 15px;
  color: var(--text);
}
.pc-meta {
  margin-top: 2px;
  font-size: 12px;
  color: var(--text-3);
  font-family: 'JetBrains Mono', monospace;
}

.pc-pages {
  margin-top: 14px;
  border-top: 1px solid var(--border);
}
.pc-pages-empty {
  margin-top: 12px;
  font-size: 12.5px;
  color: var(--text-3);
}

.pc-row {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 12px 0;
  border-bottom: 1px solid var(--border);
}
.pc-row:last-child {
  border-bottom: none;
}
.pc-row--solo {
  padding: 2px 0;
  border-bottom: none;
}
.pc-row-main {
  flex: 1;
  min-width: 0;
}
.pc-row-name {
  font-size: 13.5px;
  font-weight: 500;
  color: var(--text);
}
.pc-row-id {
  margin-left: 8px;
  font-size: 11.5px;
  color: var(--text-4);
  font-family: 'JetBrains Mono', monospace;
}

.pc-badge {
  font-size: 10.5px;
  font-weight: 600;
  letter-spacing: 0.03em;
  padding: 4px 9px;
  border-radius: 7px;
  font-family: 'JetBrains Mono', monospace;
  flex-shrink: 0;
}
.pc-badge--active {
  color: var(--green);
  background: var(--patra-green-soft);
}
.pc-badge--inactive {
  color: var(--red);
  background: var(--patra-red-soft);
}

.pc-actions {
  display: flex;
  gap: 8px;
  flex-shrink: 0;
}
.pc-btn {
  font-size: 12.5px;
  font-weight: 600;
  padding: 8px 13px;
  border-radius: 9px;
  border: 1px solid var(--border-hi);
  background: var(--surface-2);
  color: var(--text-2);
  cursor: pointer;
  transition: all 0.18s ease;
  white-space: nowrap;
}
.pc-btn:hover {
  border-color: var(--patra);
  color: var(--text);
}
.pc-btn:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}
.pc-btn--primary {
  background: var(--patra);
  border-color: transparent;
  color: white;
}
.pc-btn--primary:hover {
  filter: brightness(1.1);
  color: white;
}
.pc-btn--danger {
  color: var(--red);
}
.pc-btn--danger:hover {
  border-color: var(--red);
  color: var(--red);
}
.pc-btn--reconnect {
  color: var(--patra-3);
}
.pc-btn--reconnect:hover {
  border-color: var(--patra);
  color: var(--patra-3);
}

.pc-empty {
  text-align: center;
  padding: 40px 20px;
  color: var(--text-3);
  font-size: 13.5px;
}
.pc-empty-ic {
  font-size: 30px;
  margin-bottom: 10px;
  opacity: 0.6;
}

/* Manage Pages modal */
.pc-overlay {
  position: fixed;
  inset: 0;
  z-index: 100;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 20px;
}
.pc-overlay::before {
  content: '';
  position: absolute;
  inset: 0;
  background: var(--canvas);
  opacity: 0.74;
}
.pc-modal {
  position: relative;
  z-index: 1;
  width: 460px;
  max-width: 100%;
  max-height: 86vh;
  display: flex;
  flex-direction: column;
  background: var(--surface);
  border: 1px solid var(--border-hi);
  border-radius: 16px;
  box-shadow: var(--shadow);
  overflow: hidden;
}
.pc-modal-head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 12px;
  padding: 16px 18px;
  border-bottom: 1px solid var(--border);
}
.pc-modal-title {
  font-family: 'Space Grotesk', 'Inter', sans-serif;
  font-weight: 600;
  font-size: 15px;
  color: var(--text);
}
.pc-modal-sub {
  margin-top: 2px;
  font-size: 12px;
  color: var(--text-3);
}
.pc-modal-x {
  width: 28px;
  height: 28px;
  border-radius: 8px;
  border: 1px solid var(--border);
  background: var(--surface-2);
  color: var(--text-3);
  cursor: pointer;
  flex-shrink: 0;
}
.pc-modal-x:hover {
  border-color: var(--red);
  color: var(--red);
}
.pc-modal-body {
  padding: 16px 18px;
  overflow-y: auto;
}
.pc-check-row {
  display: flex;
  align-items: center;
  gap: 11px;
  padding: 10px 0;
  border-bottom: 1px solid var(--border);
  cursor: pointer;
}
.pc-check-row:last-of-type {
  border-bottom: none;
}
.pc-check {
  width: 16px;
  height: 16px;
  accent-color: var(--patra);
  cursor: pointer;
  flex-shrink: 0;
}
.pc-check-name {
  flex: 1;
  font-size: 13.5px;
  color: var(--text);
}
.pc-modal-note {
  margin-top: 12px;
  font-size: 11.5px;
  line-height: 1.5;
  color: var(--text-3);
}
.pc-modal-foot {
  display: flex;
  justify-content: flex-end;
  gap: 9px;
  padding: 14px 18px;
  border-top: 1px solid var(--border);
}
</style>
