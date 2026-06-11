<script>
import { mapGetters } from 'vuex';
import LoadingState from './components/widgets/LoadingState.vue';
import NetworkNotification from './components/NetworkNotification.vue';
import UpdateBanner from './components/app/UpdateBanner.vue';
import StatusBanner from './components/app/StatusBanner.vue';
import PaymentPendingBanner from './components/app/PaymentPendingBanner.vue';
import PendingEmailVerificationBanner from './components/app/PendingEmailVerificationBanner.vue';
import PatraImpersonationBanner from './components/app/PatraImpersonationBanner.vue';
import vueActionCable from './helper/actionCable';
import { useRouter } from 'vue-router';
import { useStore } from 'dashboard/composables/store';
import WootSnackbarBox from './components/SnackbarContainer.vue';
import { setColorTheme } from './helper/themeHelper';
import { LocalStorage } from 'shared/helpers/localStorage';
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
    PatraImpersonationBanner,
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
    // 3b: the dimmer slider lives in Profile settings → Appearance now; the
    // overlay stays here so it covers the whole app.
    this._patraBrightnessListener = event => {
      this.brightness = Number(event.detail) || 0;
    };
    window.addEventListener('patra:brightness', this._patraBrightnessListener);
    this.listenToThemeChanges();
    // If user locale is set, use it; otherwise use account locale
    this.setLocale(
      this.uiSettings?.locale || window.chatwootConfig.selectedLocale
    );
    // V5 P1: ONE rAF-coalesced document mousemove for both the spotlight and
    // the .lrow cursor glow (W7). Mousemove can fire >60×/s; the old pair of
    // listeners did style writes + getBoundingClientRect on every event. Now
    // the latest event is stashed and all DOM work runs at most once per frame.
    this._patraPointerEvent = null;
    this._patraPointerRaf = null;
    this._patraPointerHandler = e => {
      this._patraPointerEvent = e;
      if (this._patraPointerRaf) return;
      this._patraPointerRaf = requestAnimationFrame(() => {
        this._patraPointerRaf = null;
        const ev = this._patraPointerEvent;
        if (!ev) return;
        const spot = document.getElementById('patra-spotlight');
        if (spot) {
          // Compositor-only transform — avoids per-move layout/repaint of the
          // 460px layer that left/top triggered. The translate(-50%,-50%)
          // re-centers the glow on the cursor (was a static CSS transform).
          spot.style.transform = `translate3d(${ev.clientX}px, ${ev.clientY}px, 0) translate(-50%, -50%)`;
          spot.style.opacity = '1';
        }
        const lrow =
          ev.target && ev.target.closest && ev.target.closest('.lrow');
        if (lrow) {
          const r = lrow.getBoundingClientRect();
          lrow.style.setProperty('--mx', `${ev.clientX - r.left}px`);
          lrow.style.setProperty('--my', `${ev.clientY - r.top}px`);
        }
      });
    };
    document.addEventListener('mousemove', this._patraPointerHandler, {
      passive: true,
    });
  },
  unmounted() {
    if (this._patraBrightnessListener) {
      window.removeEventListener(
        'patra:brightness',
        this._patraBrightnessListener
      );
    }
    if (this._patraPointerHandler) {
      document.removeEventListener('mousemove', this._patraPointerHandler);
    }
    if (this._patraPointerRaf) {
      cancelAnimationFrame(this._patraPointerRaf);
      this._patraPointerRaf = null;
    }
    if (this.reconnectService) {
      this.reconnectService.disconnect();
    }
  },
  methods: {
    initializeColorTheme() {
      setColorTheme(window.matchMedia('(prefers-color-scheme: dark)').matches);
      this.syncDarkModeState();
    },
    syncDarkModeState() {
      this.isDarkMode = document.body.classList.contains('dark');
      document.documentElement.setAttribute(
        'data-theme',
        this.isDarkMode ? 'dark' : 'light'
      );
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
      style="position: fixed; pointer-events: none; z-index: 1"
    />
    <div class="patra-mesh-bg" aria-hidden="true" />
    <PatraImpersonationBanner />
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
    <!-- 3b: theme FAB + floating brightness pill removed — the one canonical
         appearance control lives in Profile settings → Appearance. The dimmer
         overlay below stays; it reacts to the patra:brightness event. -->

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
