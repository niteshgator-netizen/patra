<script setup>
import { computed, onMounted, onUnmounted, ref } from 'vue';
import ContactPanel from 'dashboard/routes/dashboard/conversation/ContactPanel.vue';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useWindowSize } from '@vueuse/core';
import { vOnClickOutside } from '@vueuse/components';

defineProps({
  currentChat: {
    required: true,
    type: Object,
  },
});

const { uiSettings, updateUISettings } = useUISettings();
const { width: windowWidth } = useWindowSize();
const spotlightRef = ref(null);

const activeTab = computed(() => {
  const { is_contact_sidebar_open: isContactSidebarOpen } = uiSettings.value;

  if (isContactSidebarOpen) {
    return 0;
  }
  return null;
});

// patra-responsive: the contact panel is an overlay drawer below Tailwind's
// 2xl (1536px) and only becomes a static in-flow column at 2xl+. Treat the
// whole drawer range as "overlay" so click-outside closes it and it never
// traps the message list behind it on a laptop.
const OVERLAY_DRAWER_MAX_WIDTH = 1536;
const isOverlayDrawer = computed(
  () => windowWidth.value < OVERLAY_DRAWER_MAX_WIDTH
);

const closeContactPanel = () => {
  if (isOverlayDrawer.value && uiSettings.value?.is_contact_sidebar_open) {
    updateUISettings({
      is_contact_sidebar_open: false,
      is_copilot_panel_open: false,
    });
  }
};

const onSpotlightMove = e => {
  const el = spotlightRef.value;
  if (!el) return;
  el.style.left = `${e.clientX}px`;
  el.style.top = `${e.clientY}px`;
  el.style.opacity = '1';
};

const onSpotlightLeave = () => {
  const el = spotlightRef.value;
  if (el) el.style.opacity = '0';
};

onMounted(() => {
  document.addEventListener('mousemove', onSpotlightMove);
  document.addEventListener('mouseleave', onSpotlightLeave);
});

onUnmounted(() => {
  document.removeEventListener('mousemove', onSpotlightMove);
  document.removeEventListener('mouseleave', onSpotlightLeave);
});
</script>

<template>
  <div
    v-on-click-outside="[
      () => closeContactPanel(),
      {
        ignore: [
          'dialog.ProseMirror-prompt-backdrop',
          '[data-popover-content]',
          '[data-popover-backdrop]',
        ],
      },
    ]"
    class="ctx conv-sidebar-patra h-full overflow-hidden flex flex-col fixed top-0 z-40 w-full max-w-sm transition-transform duration-300 ease-in-out ltr:right-0 rtl:left-0 2xl:static 2xl:w-[360px] 2xl:min-w-[360px] ltr:border-l rtl:border-r border-n-weak shadow-lg 2xl:shadow-none"
    :class="[
      {
        'md:flex': activeTab === 0,
        'md:hidden': activeTab !== 0,
      },
    ]"
  >
    <div id="spotlight" ref="spotlightRef" aria-hidden="true" />
    <div class="flex flex-1 overflow-auto min-h-0">
      <ContactPanel
        v-show="activeTab === 0"
        :conversation-id="currentChat.id"
        :inbox-id="currentChat.inbox_id"
      />
    </div>
  </div>
</template>

<style lang="scss" scoped>
@import 'dashboard/components/widgets/conversation/conversation-sidebar-patra.scss';
</style>
