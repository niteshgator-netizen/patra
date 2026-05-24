<script setup>
import { ref, computed, onMounted } from 'vue';
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
  fetchChannels();
});
</script>

<template>
  <div class="flex flex-col w-full h-full max-w-5xl px-6 py-8 mx-auto">
    <header class="mb-8">
      <h1 class="text-2xl font-semibold text-n-slate-12">Add a channel</h1>
      <p class="mt-1 text-sm text-n-slate-11">
        Connect any platform via Patra's unified OAuth. Message history syncs
        automatically once the connection is approved.
      </p>
      <p
        v-if="!isLoading && !loadError"
        class="mt-1 text-xs text-n-slate-10"
      >
        {{ connectedCount }} channel{{ connectedCount === 1 ? '' : 's' }} already connected on this account.
      </p>
      <p v-if="loadError" class="mt-2 text-sm text-n-ruby-9">
        {{ loadError }}
      </p>
    </header>

    <section
      v-for="section in SECTIONS"
      :key="section.title"
      class="mb-8"
    >
      <h2 class="mb-3 text-xs font-semibold tracking-wider uppercase text-n-slate-10">
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
  </div>
</template>
