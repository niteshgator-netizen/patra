<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import PatraChannelsAPI from 'dashboard/api/patraChannels';
import Icon from 'next/icon/Icon.vue';

// Phase H.10 item 3: full multi-platform picker for Zernio's headless OAuth.
// Organized into Social / Communication / Ads (coming soon) sections.
//
// Each card click → POST /api/v1/accounts/:id/patra/channels/connect
// { platform } → backend returns { auth_url } → we redirect.
//
// "Connected" badge shows when any inbox on this account already has
// messaging_provider == 'zernio' AND platform matches.
//
// "Coming soon" cards are disabled and just display a badge — no API call.

const SECTIONS = [
  {
    title: 'Messaging & Social',
    platforms: [
      {
        key: 'facebook',
        label: 'Facebook',
        icon: 'i-woot-messenger',
        description: 'Facebook Page Messenger threads.',
      },
      {
        key: 'instagram',
        label: 'Instagram',
        icon: 'i-woot-instagram',
        description: 'Instagram Direct messages.',
      },
      {
        key: 'tiktok',
        label: 'TikTok',
        icon: 'i-woot-tiktok',
        description: 'TikTok DMs and comment replies.',
      },
      {
        key: 'youtube',
        label: 'YouTube',
        icon: 'i-lucide-youtube',
        description: 'YouTube channel comments and DMs.',
      },
      {
        key: 'linkedin',
        label: 'LinkedIn',
        icon: 'i-lucide-linkedin',
        description: 'LinkedIn Page and Sales Navigator messages.',
      },
      {
        key: 'twitter',
        label: 'X (Twitter)',
        icon: 'i-woot-x',
        description: 'X / Twitter DMs and mentions.',
      },
      {
        key: 'threads',
        label: 'Threads',
        icon: 'i-lucide-at-sign',
        description: 'Meta Threads replies and DMs.',
      },
      {
        key: 'bluesky',
        label: 'Bluesky',
        icon: 'i-lucide-cloud',
        description: 'Bluesky mentions and notifications.',
      },
      {
        key: 'pinterest',
        label: 'Pinterest',
        icon: 'i-lucide-image',
        description: 'Pinterest business messages.',
      },
      {
        key: 'reddit',
        label: 'Reddit',
        icon: 'i-lucide-message-circle',
        description: 'Subreddit modmail and DMs.',
      },
      {
        key: 'google_business',
        label: 'Google Business',
        icon: 'i-lucide-store',
        description: 'Google Business Profile customer messages.',
      },
    ],
  },
  {
    title: 'Direct Channels',
    platforms: [
      {
        key: 'whatsapp',
        label: 'WhatsApp',
        icon: 'i-woot-whatsapp',
        description: 'WhatsApp Business numbers.',
      },
      {
        key: 'telegram',
        label: 'Telegram',
        icon: 'i-woot-telegram',
        description: 'Telegram bots and channels.',
      },
      {
        key: 'discord',
        label: 'Discord',
        icon: 'i-lucide-message-square',
        description: 'Discord server DMs and channel mentions.',
      },
    ],
  },
  {
    title: 'Ads (coming soon)',
    platforms: [
      {
        key: 'meta_ads',
        label: 'Meta Ads',
        icon: 'i-lucide-megaphone',
        description: 'Lead form replies from Facebook & Instagram ads.',
        comingSoon: true,
      },
      {
        key: 'google_ads',
        label: 'Google Ads',
        icon: 'i-lucide-search',
        description: 'Google Ads lead extensions and forms.',
        comingSoon: true,
      },
      {
        key: 'tiktok_ads',
        label: 'TikTok Ads',
        icon: 'i-lucide-trending-up',
        description: 'TikTok lead generation ads.',
        comingSoon: true,
      },
      {
        key: 'linkedin_ads',
        label: 'LinkedIn Ads',
        icon: 'i-lucide-briefcase',
        description: 'LinkedIn lead-gen form responses.',
        comingSoon: true,
      },
      {
        key: 'pinterest_ads',
        label: 'Pinterest Ads',
        icon: 'i-lucide-bar-chart-3',
        description: 'Pinterest promoted-pin lead replies.',
        comingSoon: true,
      },
      {
        key: 'x_ads',
        label: 'X Ads',
        icon: 'i-lucide-zap',
        description: 'X / Twitter promoted-tweet lead generation.',
        comingSoon: true,
      },
    ],
  },
];

const channels = ref([]);
const isLoading = ref(true);
const connectingPlatform = ref(null);
const loadError = ref('');
const { t } = useI18n();

const route = useRoute();
const router = useRouter();

// Page-selection mode: entered when Zernio bounces the browser back to
// /patra/connect-facebook with ?step=select_page&connect_token=… . We then
// list the user's Facebook pages and let them pick which ones to connect.
const selectionMode = ref(false);
const oauthCtx = ref({});
const pages = ref([]);
const selectedIds = ref(new Set());
const loadingPages = ref(false);
const saving = ref(false);
const returnError = ref('');

const apiErr = e => e?.response?.data?.error || e?.message || 'unknown error';

const goToConnectedChannels = () => {
  router.push({
    name: 'patra_facebook_accounts',
    params: { accountId: route.params.accountId },
  });
};

const togglePage = id => {
  // Reassign a fresh Set so the change is always reactive.
  const next = new Set(selectedIds.value);
  if (next.has(id)) next.delete(id);
  else next.add(id);
  selectedIds.value = next;
};

const loadPagesForSelection = async () => {
  selectionMode.value = true;
  oauthCtx.value = {
    connectToken: route.query.connect_token,
    tempToken: route.query.tempToken,
    profileId: route.query.profileId,
    userProfile: route.query.userProfile,
  };
  loadingPages.value = true;
  returnError.value = '';
  try {
    const res = await PatraChannelsAPI.fbListPages({
      connect_token: oauthCtx.value.connectToken,
      temp_token: oauthCtx.value.tempToken,
      profile_id: oauthCtx.value.profileId,
    });
    pages.value = res?.data?.pages || [];
    // Everything checked by default — the common case is "connect them all".
    selectedIds.value = new Set(pages.value.map(p => p.id));
  } catch (e) {
    returnError.value = apiErr(e);
  } finally {
    loadingPages.value = false;
  }
};

const connectSelectedPages = async () => {
  if (selectedIds.value.size === 0 || saving.value) return;
  saving.value = true;
  returnError.value = '';
  try {
    const res = await PatraChannelsAPI.fbConnectPages({
      connect_token: oauthCtx.value.connectToken,
      temp_token: oauthCtx.value.tempToken,
      profile_id: oauthCtx.value.profileId,
      user_profile: oauthCtx.value.userProfile,
      page_ids: [...selectedIds.value],
    });
    const inboxes = res?.data?.inboxes || [];
    const failures = (res?.data?.saved || []).filter(s => s && s.error);

    if (inboxes.length === 0 && failures.length > 0) {
      // Every selected page failed to save — keep the user here so they retry.
      returnError.value = `Could not connect the selected page(s): ${failures[0].error}`;
      saving.value = false;
      return;
    }

    if (inboxes.length > 0) {
      const base = `Connected ${inboxes.length} channel${inboxes.length === 1 ? '' : 's'}`;
      // Surface a partial failure so it isn't silently swallowed.
      useAlert(
        failures.length
          ? `${base}; ${failures.length} page(s) couldn't be connected.`
          : base
      );
    } else {
      // Saves reported success but no NEW inbox appeared — almost always an
      // idempotent re-run. Hedged wording so it stays truthful either way.
      useAlert('No new channels added — they may already be connected.');
    }
    goToConnectedChannels();
  } catch (e) {
    returnError.value = apiErr(e);
    saving.value = false;
  }
};

const platformIsConnected = platformKey =>
  channels.value.some(
    c => c.platform === platformKey && c.messaging_provider === 'zernio'
  );

const buttonLabel = platform => {
  if (platform.comingSoon) return 'Coming soon';
  if (connectingPlatform.value === platform.key) return 'Connecting…';
  return platformIsConnected(platform.key) ? '+ Add another' : '+ Connect';
};

const cardIsDisabled = platform =>
  platform.comingSoon || connectingPlatform.value === platform.key;

const fetchChannels = async () => {
  isLoading.value = true;
  loadError.value = '';
  try {
    const response = await PatraChannelsAPI.get();
    channels.value = response?.data?.channels || [];
  } catch (e) {
    loadError.value =
      e?.response?.data?.error || 'Failed to load existing channels.';
  } finally {
    isLoading.value = false;
  }
};

const BOT_TOKEN_PLATFORMS = new Set(['telegram']);

const connectPlatform = async platform => {
  if (platform.comingSoon) return;
  if (connectingPlatform.value) return;

  connectingPlatform.value = platform.key;
  try {
    const response = await PatraChannelsAPI.connect(platform.key);
    const authUrl = response?.data?.auth_url;
    if (authUrl) {
      window.location.href = authUrl;
      return;
    }
    if (BOT_TOKEN_PLATFORMS.has(platform.key)) {
      useAlert(t('PATRA.CHANNELS.TELEGRAM_BOT_TOKEN_COMING_SOON'));
      return;
    }
    useAlert(t('PATRA.CHANNELS.CONNECT_NO_AUTH_URL'));
  } catch (e) {
    useAlert(
      `Connect failed: ${e?.response?.data?.error || e?.message || 'unknown error'}`
    );
  } finally {
    connectingPlatform.value = null;
  }
};

const connectedCount = computed(
  () => channels.value.filter(c => c.messaging_provider === 'zernio').length
);

onMounted(() => {
  // Returning from Zernio's headless FB OAuth → show the page picker.
  // Otherwise (FB cancelled, or a normal visit) → the platform tiles.
  if (route.query.step === 'select_page' && route.query.connect_token) {
    loadPagesForSelection();
  } else {
    fetchChannels();
  }
});
</script>

<template>
  <div class="pat-page-wrap">
    <div class="pat-page-main">
      <div class="flex flex-col w-full h-full max-w-5xl px-6 py-8 mx-auto">
        <!-- Page-selection mode: pick which Facebook pages to connect -->
        <template v-if="selectionMode">
          <header class="mb-8">
            <h1 class="text-2xl font-semibold text-n-slate-12">
              Choose pages to connect
            </h1>
            <p class="mt-1 text-sm text-n-slate-11">
              Select the Facebook pages you want to manage in Patra. Each page
              becomes its own inbox — you can connect more later.
            </p>
          </header>

          <p v-if="returnError" class="mb-4 text-sm text-n-ruby-9">
            {{ returnError }}
          </p>
          <button
            v-if="returnError && pages.length === 0"
            type="button"
            class="mb-4 text-sm font-medium text-n-blue-11"
            @click="goToConnectedChannels"
          >
            Back to channels
          </button>

          <div v-if="loadingPages" class="text-sm text-n-slate-11">
            Loading your Facebook pages…
          </div>

          <template v-else>
            <div
              v-if="pages.length === 0 && !returnError"
              class="p-6 text-center border rounded-lg bg-n-background border-n-weak"
            >
              <p class="text-sm text-n-slate-11">
                No Facebook pages found — you must be an admin of at least one
                page.
              </p>
              <button
                type="button"
                class="mt-3 text-sm font-medium text-n-blue-11"
                @click="goToConnectedChannels"
              >
                Back to channels
              </button>
            </div>

            <div v-else-if="pages.length">
              <ul
                class="border rounded-lg divide-y bg-n-background border-n-weak"
              >
                <li v-for="page in pages" :key="page.id">
                  <label
                    class="flex items-center gap-3 p-4 cursor-pointer hover:bg-n-slate-2"
                  >
                    <input
                      type="checkbox"
                      class="shrink-0 size-4"
                      :checked="selectedIds.has(page.id)"
                      @change="togglePage(page.id)"
                    />
                    <span class="flex-1 min-w-0">
                      <span class="block text-sm font-medium text-n-slate-12">
                        {{ page.name }}
                      </span>
                      <span class="block text-xs text-n-slate-11 truncate">
                        <span v-if="page.username">@{{ page.username }}</span>
                        <span v-if="page.username && page.category"> · </span>
                        <span v-if="page.category">{{ page.category }}</span>
                      </span>
                    </span>
                  </label>
                </li>
              </ul>

              <div class="flex items-center gap-3 mt-6">
                <button
                  type="button"
                  class="px-4 py-2 text-sm font-medium text-white rounded-lg bg-n-blue-9 hover:bg-n-blue-10 disabled:opacity-60 disabled:cursor-not-allowed"
                  :disabled="selectedIds.size === 0 || saving"
                  @click="connectSelectedPages"
                >
                  {{
                    saving
                      ? 'Connecting…'
                      : `Connect selected (${selectedIds.size})`
                  }}
                </button>
                <button
                  type="button"
                  class="px-4 py-2 text-sm font-medium border rounded-lg text-n-slate-12 border-n-weak hover:bg-n-slate-2 disabled:opacity-60 disabled:cursor-not-allowed"
                  :disabled="saving"
                  @click="goToConnectedChannels"
                >
                  Cancel
                </button>
              </div>
            </div>
          </template>
        </template>

        <!-- Default mode: multi-platform tile picker -->
        <template v-else>
        <header class="mb-8">
          <h1 class="text-2xl font-semibold text-n-slate-12">Add a channel</h1>
          <p class="mt-1 text-sm text-n-slate-11">
            Connect any platform via Patra's unified OAuth. Message history
            syncs automatically once the connection is approved.
          </p>
          <p
            v-if="!isLoading && !loadError"
            class="mt-1 text-xs text-n-slate-10"
          >
            {{ connectedCount }} channel{{ connectedCount === 1 ? '' : 's' }}
            already connected on this account.
          </p>
          <p v-if="loadError" class="mt-2 text-sm text-n-ruby-9">
            {{ loadError }}
          </p>
        </header>

        <section v-for="section in SECTIONS" :key="section.title" class="mb-8">
          <h2
            class="mb-3 text-xs font-semibold tracking-wider uppercase text-n-slate-10"
          >
            {{ section.title }}
          </h2>
          <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
            <button
              v-for="platform in section.platforms"
              :key="platform.key"
              type="button"
              class="flex items-start gap-3 p-4 text-left transition-colors border rounded-lg bg-n-background hover:bg-n-slate-2 border-n-weak disabled:opacity-60 disabled:cursor-not-allowed disabled:hover:bg-n-background"
              :disabled="cardIsDisabled(platform)"
              @click="connectPlatform(platform)"
            >
              <span
                class="flex items-center justify-center flex-shrink-0 rounded-full size-9 bg-n-slate-2"
              >
                <Icon :icon="platform.icon" class="size-5 text-n-slate-12" />
              </span>

              <div class="flex-1 min-w-0">
                <div class="flex items-center gap-2">
                  <h3 class="text-sm font-medium text-n-slate-12">
                    {{ platform.label }}
                  </h3>
                  <span
                    v-if="platform.comingSoon"
                    class="px-1.5 py-0.5 text-[10px] font-medium rounded-full bg-n-slate-3 text-n-slate-11"
                  >
                    Soon
                  </span>
                  <span
                    v-else-if="platformIsConnected(platform.key)"
                    class="px-1.5 py-0.5 text-[10px] font-medium rounded-full bg-emerald-500/15 text-emerald-700 dark:text-emerald-300"
                  >
                    Connected
                  </span>
                </div>
                <p class="mt-0.5 text-xs text-n-slate-11 line-clamp-2">
                  {{ platform.description }}
                </p>
                <span
                  class="inline-block mt-2 text-xs font-medium"
                  :class="
                    platform.comingSoon ? 'text-n-slate-10' : 'text-n-blue-11'
                  "
                >
                  {{ buttonLabel(platform) }}
                </span>
              </div>
            </button>
          </div>
        </section>
        </template>
      </div>
    </div>
  </div>
</template>

<style scoped>
.pat-page-wrap {
  --canvas: #050409;
  --surface: #0c0b12;
  --surface-2: #131119;
  --surface-3: #1b1925;
  --surface-4: #252233;
  --border: #171520;
  --border-hi: #2e2940;
  --patra: #6e56cf;
  --patra-3: #a78bfa;
  --text: #ededf2;
  --text-2: #a8a6b6;
  --text-3: #75727f;
  --text-4: #54515e;
  --green: #3fb950;
  --red: #f85149;

  position: relative;
  min-height: 100%;
  margin-left: -24px;
  margin-right: -24px;
  padding: 0 24px 24px;
  color: var(--text);
  font-family: 'Inter', sans-serif;
  background: var(--canvas);
}

.pat-page-main {
  position: relative;
  z-index: 1;
}

.pat-page-wrap :deep(.text-heading-1),
.pat-page-wrap :deep(h1),
.pat-page-wrap :deep(h2) {
  color: var(--text) !important;
}

.pat-page-wrap :deep(.text-n-slate-12) {
  color: var(--text) !important;
}

.pat-page-wrap :deep(.text-n-slate-11) {
  color: var(--text-2) !important;
}

.pat-page-wrap :deep(.text-n-slate-10),
.pat-page-wrap :deep(.text-n-slate-9) {
  color: var(--text-3) !important;
}

.pat-page-wrap :deep(.text-n-slate-6),
.pat-page-wrap :deep(.text-n-slate-7),
.pat-page-wrap :deep(.text-n-slate-8) {
  color: var(--text-4) !important;
}

.pat-page-wrap :deep(.bg-n-surface-1),
.pat-page-wrap :deep(.bg-n-solid-1) {
  background: var(--canvas) !important;
}

.pat-page-wrap :deep(.bg-n-surface-2),
.pat-page-wrap :deep(.bg-n-solid-2),
.pat-page-wrap :deep(.bg-n-solid-3) {
  background: var(--surface) !important;
}

.pat-page-wrap :deep(.bg-n-alpha-1),
.pat-page-wrap :deep(.bg-n-alpha-2) {
  background: var(--surface-2) !important;
}

.pat-page-wrap :deep(.bg-n-slate-1),
.pat-page-wrap :deep(.bg-n-slate-2) {
  background: var(--surface-2) !important;
}

.pat-page-wrap :deep(.bg-n-slate-3) {
  background: var(--surface-3) !important;
}

.pat-page-wrap :deep(.rounded-xl.border),
.pat-page-wrap :deep(.rounded-lg.border) {
  border-color: var(--border) !important;
}

.pat-page-wrap :deep(.border-n-weak),
.pat-page-wrap :deep(.border-n-container),
.pat-page-wrap :deep(.outline-n-weak),
.pat-page-wrap :deep(.outline-n-container),
.pat-page-wrap :deep(.dark\:border-n-slate-6) {
  border-color: var(--border) !important;
  outline-color: var(--border) !important;
}

.pat-page-wrap :deep(.divide-y > *) {
  border-color: var(--border) !important;
}

.pat-page-wrap :deep(.group-hover\:bg-n-alpha-2) {
  background: var(--surface-2) !important;
  border-color: var(--border-hi) !important;
  color: var(--text-2) !important;
}

.pat-page-wrap :deep(.group:hover .group-hover\:bg-n-alpha-2) {
  background: var(--surface-3) !important;
  border-color: var(--patra) !important;
  color: var(--text) !important;
}

.pat-page-wrap :deep(thead) {
  background: var(--surface-2) !important;
}

.pat-page-wrap :deep(thead th) {
  color: var(--text-4) !important;
  border-bottom: 1px solid var(--border);
}

.pat-page-wrap :deep(tbody tr:hover) {
  background: var(--surface-2) !important;
}

.pat-page-wrap :deep(tbody td) {
  color: var(--text);
  border-color: var(--border);
}

.pat-page-wrap :deep(input),
.pat-page-wrap :deep(textarea),
.pat-page-wrap :deep(select) {
  background: var(--surface-2);
  border: 1px solid var(--border);
  color: var(--text);
  border-radius: 8px;
}

.pat-page-wrap :deep(input:focus),
.pat-page-wrap :deep(textarea:focus),
.pat-page-wrap :deep(select:focus) {
  border-color: var(--patra);
  outline: none;
  box-shadow: 0 0 0 3px rgba(110, 86, 207, 0.11);
}

.pat-page-wrap :deep(.text-n-teal-10),
.pat-page-wrap :deep(.text-n-teal-11) {
  color: var(--green) !important;
}

.pat-page-wrap :deep(.text-n-ruby-9),
.pat-page-wrap :deep(.text-n-ruby-10) {
  color: var(--red) !important;
}

.pat-page-wrap :deep(.fixed.z-50.bg-n-slate-12) {
  background: var(--surface-4) !important;
  border: 1px solid var(--border-hi);
  color: var(--text) !important;
}

.pat-page-wrap :deep(.animate-loader-pulse) {
  background: var(--surface-3) !important;
}
</style>
