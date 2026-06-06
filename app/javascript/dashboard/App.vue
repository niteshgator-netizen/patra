<script>
import { mapGetters } from 'vuex';
import LoadingState from './components/widgets/LoadingState.vue';
import NetworkNotification from './components/NetworkNotification.vue';
import UpdateBanner from './components/app/UpdateBanner.vue';
import StatusBanner from './components/app/StatusBanner.vue';
import PaymentPendingBanner from './components/app/PaymentPendingBanner.vue';
import PendingEmailVerificationBanner from './components/app/PendingEmailVerificationBanner.vue';
import vueActionCable from './helper/actionCable';
import { useRouter } from 'vue-router';
import { useStore } from 'dashboard/composables/store';
import WootSnackbarBox from './components/SnackbarContainer.vue';
import { setColorTheme } from './helper/themeHelper';
import { LocalStorage } from 'shared/helpers/localStorage';
import { LOCAL_STORAGE_KEYS } from 'dashboard/constants/localStorage';
import { isOnOnboardingView } from 'v3/helpers/RouteHelper';
import { useAccount } from 'dashboard/composables/useAccount';
import { useFontSize } from 'dashboard/composables/useFontSize';
import {
  registerSubscription,
  verifyServiceWorkerExistence,
} from './helper/pushHelper';
import ReconnectService from 'dashboard/helper/ReconnectService';
import { useUISettings } from 'dashboard/composables/useUISettings';

export default {
  name: 'App',

  components: {
    LoadingState,
    NetworkNotification,
    UpdateBanner,
    StatusBanner,
    PaymentPendingBanner,
    WootSnackbarBox,
    PendingEmailVerificationBanner,
  },
  setup() {
    const router = useRouter();
    const store = useStore();
    const { accountId } = useAccount();
    // Use the font size composable (it automatically sets up the watcher)
    const { currentFontSize } = useFontSize();
    const { uiSettings } = useUISettings();

    return {
      router,
      store,
      currentAccountId: accountId,
      currentFontSize,
      uiSettings,
    };
  },
  data() {
    return {
      latestChatwootVersion: null,
      reconnectService: null,
      isDarkMode: document.body.classList.contains('dark'),
      brightness: 0,
    };
  },
  computed: {
    ...mapGetters({
      getAccount: 'accounts/getAccount',
      isRTL: 'accounts/isRTL',
      currentUser: 'getCurrentUser',
      authUIFlags: 'getAuthUIFlags',
    }),
    hideOnOnboardingView() {
      return !isOnOnboardingView(this.$route);
    },
  },

  watch: {
    currentAccountId: {
      immediate: true,
      handler() {
        if (this.currentAccountId) {
          this.initializeAccount();
        }
      },
    },
  },
  mounted() {
    this.initializeColorTheme();
    this.syncDarkModeState();
    const savedBrightness = LocalStorage.get('patra_brightness');
    if (savedBrightness != null && savedBrightness !== '') {
      this.brightness = Number(savedBrightness) || 0;
    }
    this.listenToThemeChanges();
    // If user locale is set, use it; otherwise use account locale
    this.setLocale(
      this.uiSettings?.locale || window.chatwootConfig.selectedLocale
    );
    this.patraSpotlightMoveHandler = e => {
      const spot = document.getElementById('patra-spotlight');
      if (spot) {
        spot.style.left = `${e.clientX}px`;
        spot.style.top = `${e.clientY}px`;
        spot.style.opacity = '1';
      }
    };
    document.addEventListener('mousemove', this.patraSpotlightMoveHandler);
  },
  unmounted() {
    if (this.patraSpotlightMoveHandler) {
      document.removeEventListener('mousemove', this.patraSpotlightMoveHandler);
    }
    if (this.reconnectService) {
      this.reconnectService.disconnect();
    }
  },
  methods: {
    initializeColorTheme() {
      setColorTheme(window.matchMedia('(prefers-color-scheme: dark)').matches);
    },
    syncDarkModeState() {
      this.isDarkMode = document.body.classList.contains('dark');
      document.documentElement.setAttribute(
        'data-theme',
        this.isDarkMode ? 'dark' : 'light'
      );
    },
    toggleTheme() {
      const next = this.isDarkMode ? 'light' : 'dark';
      LocalStorage.set(LOCAL_STORAGE_KEYS.COLOR_SCHEME, next);
      setColorTheme(next === 'dark');
      this.syncDarkModeState();
    },
    applyBrightness(value) {
      this.brightness = Number(value) || 0;
      LocalStorage.set('patra_brightness', this.brightness);
    },
    listenToThemeChanges() {
      const mql = window.matchMedia('(prefers-color-scheme: dark)');
      mql.onchange = e => {
        setColorTheme(e.matches);
        this.syncDarkModeState();
      };
    },
    setLocale(locale) {
      if (locale) {
        this.$root.$i18n.locale = locale;
      }
    },
    async initializeAccount() {
      await this.$store.dispatch('accounts/get');
      this.$store.dispatch('setActiveAccount', {
        accountId: this.currentAccountId,
      });
      const account = this.getAccount(this.currentAccountId);
      const { locale, latest_chatwoot_version: latestChatwootVersion } =
        account;
      const { pubsub_token: pubsubToken } = this.currentUser || {};
      // If user locale is set, use it; otherwise use account locale
      this.setLocale(this.uiSettings?.locale || locale);
      this.latestChatwootVersion = latestChatwootVersion;
      vueActionCable.init(this.store, pubsubToken);
      this.reconnectService = new ReconnectService(this.store, this.router);
      window.reconnectService = this.reconnectService;

      verifyServiceWorkerExistence(registration =>
        registration.pushManager.getSubscription().then(subscription => {
          if (subscription) {
            registerSubscription();
          }
        })
      );
    },
  },
};
</script>

<template>
  <div
    v-if="!authUIFlags.isFetching"
    id="app"
    class="flex flex-col w-full h-screen min-h-0 bg-n-background"
    :dir="isRTL ? 'rtl' : 'ltr'"
  >
    <div
      id="patra-spotlight"
      aria-hidden="true"
      style="position: fixed; pointer-events: none; z-index: 9999"
    />
    <UpdateBanner :latest-chatwoot-version="latestChatwootVersion" />
    <StatusBanner />
    <template v-if="currentAccountId">
      <PendingEmailVerificationBanner v-if="hideOnOnboardingView" />
      <PaymentPendingBanner v-if="hideOnOnboardingView" />
    </template>
    <router-view v-slot="{ Component }">
      <transition name="fade" mode="out-in">
        <component :is="Component" />
      </transition>
    </router-view>
    <WootSnackbarBox />
    <NetworkNotification />

    <!-- Theme FAB -->
    <button
      id="patra-theme-fab"
      class="patra-theme-fab"
      type="button"
      aria-label="Toggle theme"
      @click="toggleTheme"
    >
      {{ isDarkMode ? '☀️' : '🌙' }}
    </button>

    <!-- Brightness control -->
    <div id="patra-bright-ctl" class="patra-bright-ctl">
      <input
        type="range"
        min="0"
        max="80"
        :value="brightness"
        class="patra-bright-slider"
        @input="applyBrightness($event.target.value)"
      />
      <span
        class="patra-bright-toggle"
        role="button"
        tabindex="0"
        @click="applyBrightness(brightness > 0 ? 0 : 30)"
        @keydown.enter.space.prevent="
          applyBrightness(brightness > 0 ? 0 : 30)
        "
      >
        🔅
      </span>
    </div>

    <!-- Dimmer overlay -->
    <div id="patra-dimmer" :style="{ opacity: brightness / 100 }" />

    <!-- Mobile notice -->
    <div class="patra-mobile-note">
      📱 Full agent view is desktop-first — mobile gets a stacked layout
    </div>
  </div>
  <LoadingState v-else />
</template>

<style lang="scss">
@import './assets/scss/app';

.v-popper--theme-tooltip .v-popper__inner {
  background: black !important;
  font-size: 0.75rem;
  padding: 4px 8px !important;
  border-radius: 6px;
  font-weight: 400;
}

.v-popper--theme-tooltip .v-popper__arrow-container {
  display: none;
}
</style>
