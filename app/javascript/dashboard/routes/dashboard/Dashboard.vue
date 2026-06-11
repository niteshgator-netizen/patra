<script>
import {
  defineAsyncComponent,
  ref,
  computed,
  watch,
  onMounted,
  onBeforeUnmount,
} from 'vue';
import { useStore } from 'dashboard/composables/store';
import {
  updateTabTitle,
  getTotalUnreadCount,
} from 'dashboard/helper/tabTitleHelper';

import NextSidebar from 'next/sidebar/Sidebar.vue';
import WootKeyShortcutModal from 'dashboard/components/widgets/modal/WootKeyShortcutModal.vue';
import AddAccountModal from 'dashboard/components/app/AddAccountModal.vue';
import UpgradePage from 'dashboard/routes/dashboard/upgrade/UpgradePage.vue';

import { useUISettings } from 'dashboard/composables/useUISettings';
import { useAccount } from 'dashboard/composables/useAccount';
import { useWindowSize } from '@vueuse/core';

import wootConstants from 'dashboard/constants/globals';

const CommandBar = defineAsyncComponent(
  () => import('./commands/commandbar.vue')
);

const FloatingCallWidget = defineAsyncComponent(
  () => import('dashboard/components/widgets/FloatingCallWidget.vue')
);

import CopilotLauncher from 'dashboard/components-next/copilot/CopilotLauncher.vue';
import CopilotContainer from 'dashboard/components/copilot/CopilotContainer.vue';

import MobileSidebarLauncher from 'dashboard/components-next/sidebar/MobileSidebarLauncher.vue';
import { useCallsStore } from 'dashboard/stores/calls';

export default {
  components: {
    NextSidebar,
    CommandBar,
    WootKeyShortcutModal,
    AddAccountModal,
    UpgradePage,
    CopilotLauncher,
    CopilotContainer,
    FloatingCallWidget,
    MobileSidebarLauncher,
  },
  setup() {
    const upgradePageRef = ref(null);
    const { uiSettings, updateUISettings } = useUISettings();
    const { accountId } = useAccount();
    const { width: windowWidth } = useWindowSize();
    const callsStore = useCallsStore();
    const store = useStore();

    const syncTabTitle = () => {
      updateTabTitle(getTotalUnreadCount(store.getters.getAllConversations));
    };

    watch(() => store.getters.getAllConversations, syncTabTitle, {
      deep: true,
    });

    let spotlightMouseMoveHandler = null;
    let spotlightMouseLeaveHandler = null;

    onMounted(() => {
      syncTabTitle();
      const spotlight = document.getElementById('patra-global-spotlight');
      if (spotlight) {
        /* Perf pass 2: rAF-coalesced + compositor-only transform. The old
           handler wrote left/top per mousemove (uncapped, layout-triggering
           position changes on a 460px blurred fixed layer) — the same bug
           P1 fixed for App.vue's spotlight, duplicated here. */
        let spotRaf = null;
        let spotEvent = null;
        spotlightMouseMoveHandler = e => {
          spotEvent = e;
          if (spotRaf) return;
          spotRaf = requestAnimationFrame(() => {
            spotRaf = null;
            const ev = spotEvent;
            if (!ev) return;
            spotlight.style.transform = `translate3d(${ev.clientX}px, ${ev.clientY}px, 0) translate(-50%, -50%)`;
            spotlight.style.opacity = '1';
          });
        };
        spotlightMouseLeaveHandler = () => {
          // Cancel any pending frame so it can't re-light after leave.
          if (spotRaf) {
            cancelAnimationFrame(spotRaf);
            spotRaf = null;
          }
          spotEvent = null;
          spotlight.style.opacity = '0';
        };
        document.addEventListener('mousemove', spotlightMouseMoveHandler, {
          passive: true,
        });
        document.addEventListener('mouseleave', spotlightMouseLeaveHandler);
      }

      window.addEventListener('load', () => {
        document
          .querySelectorAll(
            '.pat-stat-card, .patra-kpi, .pat-game-card, .pat-train-stat'
          )
          .forEach((el, i) => {
            el.style.animationDelay = `${Math.min(i, 10) * 0.05}s`;
          });
        document.querySelectorAll('.pat-stat-card, .patra-kpi').forEach(el => {
          el.addEventListener('mousemove', e => {
            const r = el.getBoundingClientRect();
            el.style.setProperty('--gx', `${e.clientX - r.left}px`);
            el.style.setProperty('--gy', `${e.clientY - r.top}px`);
          });
        });
      });
    });

    onBeforeUnmount(() => {
      updateTabTitle(0);
      if (spotlightMouseMoveHandler) {
        document.removeEventListener('mousemove', spotlightMouseMoveHandler);
      }
      if (spotlightMouseLeaveHandler) {
        document.removeEventListener('mouseleave', spotlightMouseLeaveHandler);
      }
    });

    return {
      uiSettings,
      updateUISettings,
      accountId,
      upgradePageRef,
      windowWidth,
      hasActiveCall: computed(() => callsStore.hasActiveCall),
      hasIncomingCall: computed(() => callsStore.hasIncomingCall),
    };
  },
  data() {
    return {
      showAccountModal: false,
      showCreateAccountModal: false,
      showShortcutModal: false,
      isMobileSidebarOpen: false,
    };
  },
  computed: {
    isSmallScreen() {
      return this.windowWidth < wootConstants.SMALL_SCREEN_BREAKPOINT;
    },
    showUpgradePage() {
      return this.upgradePageRef?.shouldShowUpgradePage;
    },
    bypassUpgradePage() {
      return [
        'billing_settings_index',
        'settings_inbox_list',
        'general_settings_index',
        'agent_list',
      ].includes(this.$route.name);
    },
    previouslyUsedDisplayType() {
      const {
        previously_used_conversation_display_type: conversationDisplayType,
      } = this.uiSettings;
      return conversationDisplayType;
    },
  },
  watch: {
    isSmallScreen: {
      handler() {
        const { LAYOUT_TYPES } = wootConstants;
        if (window.innerWidth <= wootConstants.SMALL_SCREEN_BREAKPOINT) {
          this.updateUISettings({
            conversation_display_type: LAYOUT_TYPES.EXPANDED,
          });
        } else {
          this.updateUISettings({
            conversation_display_type: this.previouslyUsedDisplayType,
          });
        }
      },
      immediate: true,
    },
  },
  methods: {
    toggleMobileSidebar() {
      this.isMobileSidebarOpen = !this.isMobileSidebarOpen;
    },
    closeMobileSidebar() {
      this.isMobileSidebarOpen = false;
    },
    openCreateAccountModal() {
      this.showAccountModal = false;
      this.showCreateAccountModal = true;
    },
    closeCreateAccountModal() {
      this.showCreateAccountModal = false;
    },
    toggleAccountModal() {
      this.showAccountModal = !this.showAccountModal;
    },
    toggleKeyShortcutModal() {
      this.showShortcutModal = true;
    },
    closeKeyShortcutModal() {
      this.showShortcutModal = false;
    },
  },
};
</script>

<template>
  <div class="flex flex-grow overflow-hidden text-n-slate-12">
    <div class="patra-mesh-bg" aria-hidden="true" />
    <div
      id="patra-global-spotlight"
      class="patra-spotlight"
      aria-hidden="true"
    />
    <NextSidebar
      :is-mobile-sidebar-open="isMobileSidebarOpen"
      @toggle-account-modal="toggleAccountModal"
      @open-key-shortcut-modal="toggleKeyShortcutModal"
      @close-key-shortcut-modal="closeKeyShortcutModal"
      @show-create-account-modal="openCreateAccountModal"
      @close-mobile-sidebar="closeMobileSidebar"
    />

    <main
      class="pat-dashboard-main flex flex-1 h-full w-full min-h-0 px-0 overflow-hidden"
    >
      <UpgradePage
        v-show="showUpgradePage"
        ref="upgradePageRef"
        :bypass-upgrade-page="bypassUpgradePage"
      >
        <MobileSidebarLauncher
          :is-mobile-sidebar-open="isMobileSidebarOpen"
          @toggle="toggleMobileSidebar"
        />
      </UpgradePage>
      <template v-if="!showUpgradePage">
        <router-view />
        <CommandBar />
        <CopilotLauncher />
        <MobileSidebarLauncher
          :is-mobile-sidebar-open="isMobileSidebarOpen"
          @toggle="toggleMobileSidebar"
        />
        <CopilotContainer />
        <FloatingCallWidget v-if="hasActiveCall || hasIncomingCall" />
      </template>
      <AddAccountModal
        :show="showCreateAccountModal"
        @close-account-create-modal="closeCreateAccountModal"
      />
      <WootKeyShortcutModal
        v-model:show="showShortcutModal"
        @close="closeKeyShortcutModal"
        @clickaway="closeKeyShortcutModal"
      />
    </main>
  </div>
</template>

<style scoped>
.pat-dashboard-main {
  position: relative;
  z-index: 1;
  background: transparent !important;
  color: #ededf2;
}
</style>

<style>
.pat-page-wrap,
.pat-page-main {
  position: relative;
  z-index: 1;
}

.pat-page-wrap :deep(.card),
.pat-page-wrap :deep([class*='card']),
.pat-page-wrap :deep(.bg-n-solid-2),
.pat-page-wrap :deep(.bg-n-solid-3) {
  background: #0c0b12 !important;
  border: 1px solid #171520 !important;
  border-radius: 14px !important;
  transition:
    border-color 0.2s,
    box-shadow 0.2s,
    transform 0.2s;
}

.pat-page-wrap :deep(.card):hover,
.pat-page-wrap :deep([class*='card']):hover {
  border-color: #2e2940 !important;
  box-shadow: 0 8px 24px rgba(0, 0, 0, 0.3);
  transform: translateY(-1px);
}

.pat-page-wrap :deep(h1),
.pat-page-wrap :deep(h2),
.pat-page-wrap :deep(.text-2xl),
.pat-page-wrap :deep(.text-xl) {
  font-family: 'Space Grotesk', sans-serif !important;
  letter-spacing: -0.01em;
}

.pat-page-wrap :deep(input:not([type='checkbox']):not([type='radio'])),
.pat-page-wrap :deep(select),
.pat-page-wrap :deep(textarea) {
  background: #050409 !important;
  border: 1px solid #171520 !important;
  border-radius: 10px !important;
  color: #ededf2 !important;
  transition:
    border-color 0.2s,
    box-shadow 0.2s;
}

.pat-page-wrap :deep(input:focus),
.pat-page-wrap :deep(select:focus),
.pat-page-wrap :deep(textarea:focus) {
  border-color: #6e56cf !important;
  box-shadow: 0 0 0 3px rgba(110, 86, 207, 0.15) !important;
  outline: none !important;
}

.pat-page-wrap :deep(button.bg-n-brand),
.pat-page-wrap :deep(button[class*='primary']),
.pat-page-wrap :deep(.btn-primary) {
  background: linear-gradient(135deg, #6e56cf, #5b45b0) !important;
  border: none !important;
  color: #fff !important;
  border-radius: 10px !important;
  transition:
    transform 0.15s,
    box-shadow 0.15s;
}

.pat-page-wrap :deep(button.bg-n-brand):hover,
.pat-page-wrap :deep(button[class*='primary']):hover {
  transform: translateY(-1px);
  box-shadow: 0 4px 12px rgba(110, 86, 207, 0.3);
}

.pat-page-wrap :deep(table) {
  border-collapse: collapse;
}

.pat-page-wrap :deep(th) {
  color: #75727f !important;
  font-size: 11px !important;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  border-bottom: 1px solid #171520 !important;
}

.pat-page-wrap :deep(td) {
  border-bottom: 1px solid #171520 !important;
}

.pat-page-wrap :deep(tr):hover {
  background: #1b1925 !important;
}

.pat-page-wrap :deep(::-webkit-scrollbar) {
  width: 6px;
}

.pat-page-wrap :deep(::-webkit-scrollbar-track) {
  background: transparent;
}

.pat-page-wrap :deep(::-webkit-scrollbar-thumb) {
  background: #2e2940;
  border-radius: 3px;
}
</style>
