<script setup>
import { ref, computed, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import PatraChannelsAPI from 'dashboard/api/patraChannels';
import Icon from 'next/icon/Icon.vue';

// Replaces the old FB-only PatraConnectFacebook.vue. Lists the platforms
// Patra supports via Zernio's headless OAuth (facebook / instagram /
// whatsapp / telegram). Clicking a card kicks off the OAuth handshake:
//   POST /api/v1/accounts/:id/patra/channels/connect { platform }
// → backend returns { auth_url } and we redirect window.location.
//
// "Connected" badge appears when any inbox on this account already has
// messaging_provider == 'zernio' AND platform matches.

const PLATFORMS = [
  {
    key: 'facebook',
    label: 'Facebook',
    icon: 'i-woot-messenger',
    description: 'Connect a Facebook Page and route Messenger threads into Patra.',
  },
  {
    key: 'instagram',
    label: 'Instagram',
    icon: 'i-woot-instagram',
    description: 'Receive Instagram Direct messages and reply from Patra.',
  },
  {
    key: 'whatsapp',
    label: 'WhatsApp',
    icon: 'i-woot-whatsapp',
    description: 'Connect a WhatsApp Business number for live agent replies.',
  },
  {
    key: 'telegram',
    label: 'Telegram',
    icon: 'i-woot-telegram',
    description: 'Bring a Telegram bot or channel into the Patra unified inbox.',
  },
];

const channels = ref([]);
const isLoading = ref(true);
const connectingPlatform = ref(null);
const loadError = ref('');

const platformIsConnected = platform =>
  channels.value.some(
    c => c.platform === platform && c.messaging_provider === 'zernio'
  );

const buttonLabel = platform => {
  if (connectingPlatform.value === platform) return 'Connecting…';
  return platformIsConnected(platform) ? '+ Add another' : '+ Connect';
};

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

const connectPlatform = async platform => {
  if (connectingPlatform.value) return;

  connectingPlatform.value = platform;
  try {
    const response = await PatraChannelsAPI.connect(platform);
    const authUrl = response?.data?.auth_url;
    if (authUrl) {
      window.location.href = authUrl;
      return;
    }
    useAlert('Connect failed: no auth URL returned by Zernio.');
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
  <div class="flex flex-col w-full h-full max-w-3xl px-6 py-8 mx-auto">
    <header class="mb-6">
      <h1 class="text-2xl font-semibold text-n-slate-12">Add a channel</h1>
      <p class="mt-1 text-sm text-n-slate-11">
        Connect a Facebook Page, Instagram account, WhatsApp business number,
        or Telegram bot. Patra will sync the message history automatically.
      </p>
      <p
        v-if="!isLoading && !loadError"
        class="mt-1 text-xs text-n-slate-10"
      >
        {{ connectedCount }} channel{{ connectedCount === 1 ? '' : 's' }} already connected on this account.
      </p>
      <p
        v-if="loadError"
        class="mt-2 text-sm text-n-ruby-9"
      >
        {{ loadError }}
      </p>
    </header>

    <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
      <button
        v-for="platform in PLATFORMS"
        :key="platform.key"
        type="button"
        class="flex items-start gap-4 p-5 text-left transition-colors border rounded-lg bg-n-background hover:bg-n-slate-2 border-n-weak disabled:opacity-60 disabled:cursor-not-allowed"
        :disabled="connectingPlatform === platform.key"
        @click="connectPlatform(platform.key)"
      >
        <span
          class="flex items-center justify-center flex-shrink-0 rounded-full size-10 bg-n-slate-2"
        >
          <Icon :icon="platform.icon" class="size-6 text-n-slate-12" />
        </span>

        <div class="flex-1 min-w-0">
          <div class="flex items-center gap-2">
            <h3 class="text-base font-medium text-n-slate-12">
              {{ platform.label }}
            </h3>
            <span
              v-if="platformIsConnected(platform.key)"
              class="px-2 py-0.5 text-xs font-medium rounded-full bg-emerald-500/15 text-emerald-700 dark:text-emerald-300"
            >
              Connected
            </span>
          </div>
          <p class="mt-1 text-sm text-n-slate-11">
            {{ platform.description }}
          </p>
          <span
            class="inline-block mt-3 text-sm font-medium text-n-blue-11"
          >
            {{ buttonLabel(platform.key) }}
          </span>
        </div>
      </button>
    </div>
  </div>
</template>
