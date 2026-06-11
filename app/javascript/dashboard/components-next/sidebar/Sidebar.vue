<script setup>
import { h, ref, computed, onMounted } from 'vue';
import { provideSidebarContext, useSidebarResize } from './provider';
import { useAccount } from 'dashboard/composables/useAccount';
import { useKbd } from 'dashboard/composables/utils/useKbd';
import { useMapGetter } from 'dashboard/composables/store';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useSidebarKeyboardShortcuts } from './useSidebarKeyboardShortcuts';
import { vOnClickOutside } from '@vueuse/components';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { useWindowSize, useEventListener } from '@vueuse/core';

import Button from 'dashboard/components-next/button/Button.vue';
import SidebarGroup from './SidebarGroup.vue';
import SidebarProfileMenu from './SidebarProfileMenu.vue';
import SidebarChangelogCard from './SidebarChangelogCard.vue';
import SidebarChangelogButton from './SidebarChangelogButton.vue';
import ChannelLeaf from './ChannelLeaf.vue';
import ChannelIcon from 'next/icon/ChannelIcon.vue';
import SidebarAccountSwitcher from './SidebarAccountSwitcher.vue';
import Logo from 'next/icon/Logo.vue';
import ComposeConversation from 'dashboard/components-next/NewConversation/ComposeConversation.vue';
import PatraChannelsAPI from 'dashboard/api/patraChannels';
import SidebarQuickStats from 'dashboard/components/widgets/conversation/SidebarQuickStats.vue';

const props = defineProps({
  isMobileSidebarOpen: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits([
  'closeKeyShortcutModal',
  'openKeyShortcutModal',
  'showCreateAccountModal',
  'closeMobileSidebar',
]);

const { accountScopedRoute, accountScopedUrl, isOnChatwootCloud } =
  useAccount();
const store = useStore();
const searchShortcut = useKbd([`$mod`, 'k']);
const { t } = useI18n();

const isACustomBrandedInstance = useMapGetter(
  'globalConfig/isACustomBrandedInstance'
);
const isRTL = useMapGetter('accounts/isRTL');

const { width: windowWidth } = useWindowSize();
const isMobile = computed(() => windowWidth.value < 768);

const accountId = useMapGetter('getCurrentAccountId');
const isFeatureEnabledonAccount = useMapGetter(
  'accounts/isFeatureEnabledonAccount'
);

const hasAdvancedAssignment = computed(() => {
  return isFeatureEnabledonAccount.value(
    accountId.value,
    FEATURE_FLAGS.ADVANCED_ASSIGNMENT
  );
});

const toggleShortcutModalFn = show => {
  if (show) {
    emit('openKeyShortcutModal');
  } else {
    emit('closeKeyShortcutModal');
  }
};

useSidebarKeyboardShortcuts(toggleShortcutModalFn);

const expandedItem = ref(null);

const setExpandedItem = name => {
  expandedItem.value = expandedItem.value === name ? null : name;
};

const {
  sidebarWidth,
  isCollapsed,
  setSidebarWidth,
  saveWidth,
  snapToCollapsed,
  snapToExpanded,
  COLLAPSED_THRESHOLD,
} = useSidebarResize();

// On mobile, sidebar is always expanded (flyout mode)
const isEffectivelyCollapsed = computed(
  () => !isMobile.value && isCollapsed.value
);

// Resize handle logic
const isResizing = ref(false);
const startX = ref(0);
const startWidth = ref(0);

provideSidebarContext({
  expandedItem,
  setExpandedItem,
  isCollapsed: isEffectivelyCollapsed,
  sidebarWidth,
  isResizing,
});

// Get clientX from mouse or touch event
const getClientX = event =>
  event.touches ? event.touches[0].clientX : event.clientX;

const onResizeStart = event => {
  isResizing.value = true;
  startX.value = getClientX(event);
  startWidth.value = sidebarWidth.value;
  Object.assign(document.body.style, {
    cursor: 'col-resize',
    userSelect: 'none',
  });
  // Prevent default to avoid scrolling on touch
  event.preventDefault();
};

const onResizeMove = event => {
  if (!isResizing.value) return;

  const delta = isRTL.value
    ? startX.value - getClientX(event)
    : getClientX(event) - startX.value;
  setSidebarWidth(startWidth.value + delta);
};

const onResizeEnd = () => {
  if (!isResizing.value) return;

  isResizing.value = false;
  Object.assign(document.body.style, { cursor: '', userSelect: '' });

  // Snap to collapsed state if below threshold
  if (sidebarWidth.value < COLLAPSED_THRESHOLD) {
    snapToCollapsed();
  } else {
    saveWidth();
  }
};

const onResizeHandleDoubleClick = () => {
  if (isCollapsed.value) snapToExpanded();
  else snapToCollapsed();
};

// Support both mouse and touch events
useEventListener(document, 'mousemove', onResizeMove);
useEventListener(document, 'mouseup', onResizeEnd);
useEventListener(document, 'touchmove', onResizeMove, { passive: false });
useEventListener(document, 'touchend', onResizeEnd);

const inboxes = useMapGetter('inboxes/getInboxes');
const labels = useMapGetter('labels/getLabelsOnSidebar');
const teams = useMapGetter('teams/getMyTeams');
const contactCustomViews = useMapGetter('customViews/getContactCustomViews');
const conversationCustomViews = useMapGetter(
  'customViews/getConversationCustomViews'
);

// Per-inbox live/idle status (from /patra/channels, Phase H.3 endpoint).
// Best-effort: a failed fetch just means status dots don't render — the
// rest of the sidebar works fine.
const channelStatuses = ref({});

const fetchChannelStatuses = async () => {
  try {
    const response = await PatraChannelsAPI.get();
    const map = {};
    (response.data?.channels || []).forEach(c => {
      // Coerce to Number on the WRITE side so the read-side lookup
      // (channelStatuses.value[Number(inbox.id)]) always matches —
      // belt-and-suspenders against Vuex/JSON edge cases where one side
      // could end up as a string and the other an integer.
      map[Number(c.id)] = c.status;
    });
    channelStatuses.value = map;
  } catch (e) {
    // silent — sidebar still works without dots
  }
};

onMounted(() => {
  store.dispatch('labels/get');
  store.dispatch('inboxes/get');
  store.dispatch('notifications/unReadCount');
  store.dispatch('teams/get');
  store.dispatch('attributes/get');
  store.dispatch('customViews/get', 'conversation');
  store.dispatch('customViews/get', 'contact');
  fetchChannelStatuses();

  if (!isMobile.value && sidebarWidth.value !== 66) {
    setSidebarWidth(66);
    saveWidth();
  }
});

const sortedInboxes = computed(() =>
  inboxes.value.slice().sort((a, b) => a.name.localeCompare(b.name))
);

const currentRole = useMapGetter('getCurrentRole');

const showAddChannel = computed(() => currentRole.value === 'administrator');

// Replaces the old FB-only patraFacebookConnectNav. A single generic
// "+ Add Channel" entry that lands on PatraAddChannel.vue — the multi-
// platform picker for Zernio's headless OAuth (facebook / instagram /
// whatsapp / telegram). Label is hardcoded since the old i18n key
// PATRA_CONNECT_FACEBOOK.SIDEBAR_LINK still resolved to "+ Connect
// Facebook" and was misleading.
const addChannelNav = computed(() =>
  showAddChannel.value
    ? [
        {
          name: 'PatraAddChannel',
          label: 'Add Channel',
          icon: 'i-lucide-plus',
          to: accountScopedRoute('patra_connect_facebook'),
        },
      ]
    : []
);

const closeMobileSidebar = () => {
  if (!props.isMobileSidebarOpen) return;
  emit('closeMobileSidebar');
};

const menuItems = computed(() => {
  return [
    {
      name: 'PatraDashboard',
      label: t('PATRA.DASHBOARD.NAV'),
      icon: 'i-lucide-layout-dashboard',
      to: accountScopedRoute('patra_owner_dashboard'),
    },
    // Phase H.10 item 1: "+ Add Channel" promoted to a top-level primary
    // action. Sits above Conversation so admins always see it. Routes to
    // PatraAddChannel.vue (multi-platform picker).
    ...addChannelNav.value,
    {
      name: 'Conversation',
      label: t('SIDEBAR.CONVERSATIONS'),
      icon: 'i-lucide-message-circle',
      getterKeys: { count: 'conversationStats/getAllCount' },
      children: [
        {
          name: 'All',
          label: t('SIDEBAR.ALL_CONVERSATIONS'),
          activeOn: ['inbox_conversation'],
          to: accountScopedRoute('home'),
        },
        {
          name: 'Mentions',
          label: t('SIDEBAR.MENTIONED_CONVERSATIONS'),
          activeOn: ['conversation_through_mentions'],
          to: accountScopedRoute('conversation_mentions'),
        },
        {
          name: 'Participating',
          label: t('SIDEBAR.PARTICIPATING_CONVERSATIONS'),
          activeOn: ['conversation_through_participating'],
          to: accountScopedRoute('conversation_participating'),
        },
        {
          name: 'Unattended',
          activeOn: ['conversation_through_unattended'],
          label: t('SIDEBAR.UNATTENDED_CONVERSATIONS'),
          to: accountScopedRoute('conversation_unattended'),
        },
        {
          name: 'Folders',
          label: t('SIDEBAR.CUSTOM_VIEWS_FOLDER'),
          icon: 'i-lucide-folder',
          activeOn: ['conversations_through_folders'],
          children: conversationCustomViews.value.map(view => ({
            name: `${view.name}-${view.id}`,
            label: view.name,
            to: accountScopedRoute('folder_conversations', { id: view.id }),
          })),
        },
        {
          name: 'Teams',
          label: t('SIDEBAR.TEAMS'),
          icon: 'i-lucide-users',
          activeOn: ['conversations_through_team'],
          children: teams.value.map(team => ({
            name: `${team.name}-${team.id}`,
            label: team.name,
            to: accountScopedRoute('team_conversations', { teamId: team.id }),
          })),
        },
        {
          name: 'Channels',
          label: t('SIDEBAR.CHANNELS'),
          icon: 'i-lucide-mailbox',
          activeOn: ['conversation_through_inbox', 'patra_connect_facebook'],
          children: [
            // "+ Add Channel" moved to the top-level menu (Phase H.10 item 1).
            // The Channels section now lists connected inboxes only.
            ...sortedInboxes.value.map(inbox => ({
              name: `${inbox.name}-${inbox.id}`,
              label: inbox.name,
              icon: h(ChannelIcon, { inbox, class: 'size-[16px]' }),
              to: accountScopedRoute('inbox_dashboard', { inbox_id: inbox.id }),
              component: leafProps =>
                h(ChannelLeaf, {
                  label: leafProps.label,
                  active: leafProps.active,
                  inbox,
                  live: channelStatuses.value[Number(inbox.id)] === 'live',
                }),
            })),
          ],
        },
        {
          name: 'Labels',
          label: t('SIDEBAR.LABELS'),
          icon: 'i-lucide-tag',
          activeOn: ['conversations_through_label'],
          children: labels.value.map(label => ({
            name: `${label.title}-${label.id}`,
            label: label.title,
            icon: h('span', {
              class: `size-[8px] rounded-sm`,
              style: { backgroundColor: label.color },
            }),
            to: accountScopedRoute('label_conversations', {
              label: label.title,
            }),
          })),
        },
      ],
    },
    {
      name: 'Contacts',
      label: t('SIDEBAR.CONTACTS'),
      icon: 'i-lucide-contact',
      children: [
        {
          name: 'All Contacts',
          label: t('SIDEBAR.ALL_CONTACTS'),
          to: accountScopedRoute(
            'contacts_dashboard_index',
            {},
            { page: 1, search: undefined }
          ),
          activeOn: ['contacts_dashboard_index', 'contacts_edit'],
        },
        {
          name: 'Active',
          label: t('SIDEBAR.ACTIVE'),
          to: accountScopedRoute('contacts_dashboard_active'),
          activeOn: ['contacts_dashboard_active'],
        },
        {
          name: 'Segments',
          icon: 'i-lucide-group',
          label: t('SIDEBAR.CUSTOM_VIEWS_SEGMENTS'),
          children: contactCustomViews.value.map(view => ({
            name: `${view.name}-${view.id}`,
            label: view.name,
            to: accountScopedRoute(
              'contacts_dashboard_segments_index',
              { segmentId: view.id },
              { page: 1 }
            ),
            activeOn: [
              'contacts_dashboard_segments_index',
              'contacts_edit_segment',
            ],
          })),
        },
        {
          name: 'Tagged With',
          icon: 'i-lucide-tag',
          label: t('SIDEBAR.TAGGED_WITH'),
          children: labels.value.map(label => ({
            name: `${label.title}-${label.id}`,
            label: label.title,
            icon: h('span', {
              class: `size-[8px] rounded-sm`,
              style: { backgroundColor: label.color },
            }),
            to: accountScopedRoute(
              'contacts_dashboard_labels_index',
              { label: label.title },
              { page: 1, search: undefined }
            ),
            activeOn: [
              'contacts_dashboard_labels_index',
              'contacts_edit_label',
            ],
          })),
        },
      ],
    },
    {
      name: 'Companies',
      label: t('SIDEBAR.COMPANIES'),
      icon: 'i-lucide-building-2',
      children: [
        {
          name: 'All Companies',
          label: t('SIDEBAR.ALL_COMPANIES'),
          to: accountScopedRoute(
            'companies_dashboard_index',
            {},
            { page: 1, search: undefined }
          ),
          activeOn: ['companies_dashboard_index', 'companies_dashboard_show'],
        },
      ],
    },
    {
      name: 'PatraReports',
      label: t('PATRA.REPORTS.NAV'),
      icon: 'i-lucide-chart-spline',
      to: accountScopedRoute('patra_reports'),
    },
    // Phase H.10 item 5: Campaigns nav entry hidden. Routes still registered;
    // only the sidebar link is removed.
    {
      name: 'Automations',
      label: 'Automations & Flows',
      icon: 'i-lucide-workflow',
      to: accountScopedRoute('automation_list'),
      activeOn: [
        'automation_list',
        'patra_flow_list',
        'patra_flow_builder_new',
        'patra_flow_builder',
      ],
    },
    {
      name: 'GamesHealth',
      label: 'Games & Health',
      icon: 'i-lucide-gamepad-2',
      to: accountScopedRoute('settings_integrations_games'),
      activeOn: ['settings_integrations_games'],
    },
    {
      name: 'PatraAiTraining',
      label: 'Patra AI Training',
      icon: 'i-lucide-brain',
      to: accountScopedRoute('patra_ai_training'),
      activeOn: ['patra_ai_training'],
    },
    {
      // Working feature routes that previously had no rail entry (URL-only).
      // Grouped under one expandable item so the icon rail doesn't overflow.
      name: 'PatraMore',
      label: 'More',
      icon: 'i-lucide-layout-grid',
      children: [
        {
          name: 'Knowledge Base',
          label: 'Knowledge Base',
          icon: 'i-lucide-book-open',
          to: accountScopedRoute('patra_knowledge'),
          activeOn: ['patra_knowledge'],
        },
        {
          name: 'Cashier Queue',
          label: 'Cashier Queue',
          icon: 'i-lucide-coins',
          to: accountScopedRoute('patra_cashier_queue'),
          activeOn: ['patra_cashier_queue'],
        },
        {
          name: 'Leaderboard',
          label: 'Leaderboard',
          icon: 'i-lucide-trophy',
          to: accountScopedRoute('patra_leaderboard'),
          activeOn: ['patra_leaderboard'],
        },
        {
          name: 'Backup Pages',
          label: 'Backup Pages',
          icon: 'i-lucide-archive',
          to: accountScopedRoute('patra_backup_pages'),
          activeOn: ['patra_backup_pages'],
        },
        {
          name: 'Broadcasts',
          label: 'Broadcasts',
          icon: 'i-lucide-megaphone',
          to: accountScopedRoute('campaigns_livechat_index'),
          activeOn: ['campaigns_livechat_index'],
        },
        {
          name: 'Audit Logs',
          label: 'Audit Logs',
          icon: 'i-lucide-scroll-text',
          to: accountScopedRoute('auditlogs_list'),
          activeOn: ['auditlogs_list'],
        },
      ],
    },
    {
      name: 'Settings',
      label: t('PATRA.SETTINGS.NAV_TITLE'),
      icon: 'i-lucide-bolt',
      navVariant: 'snav',
      children: [
        {
          name: 'Settings Account Settings',
          label: t('SIDEBAR.ACCOUNT_SETTINGS'),
          icon: 'i-lucide-briefcase',
          to: accountScopedRoute('general_settings_index'),
        },
        {
          name: 'Settings Facebook Accounts',
          label: 'Facebook Accounts',
          icon: 'i-woot-messenger',
          to: accountScopedRoute('patra_facebook_accounts'),
        },
        // {
        //   name: 'Settings Captain',
        //   label: t('SIDEBAR.CAPTAIN_AI'),
        //   icon: 'i-woot-captain',
        //   to: accountScopedRoute('captain_settings_index'),
        // },
        {
          name: 'Settings Agents',
          label: t('SIDEBAR.AGENTS'),
          icon: 'i-lucide-square-user',
          to: accountScopedRoute('agent_list'),
        },
        {
          name: 'Settings Teams',
          label: t('SIDEBAR.TEAMS'),
          icon: 'i-lucide-users',
          activeOn: [
            'settings_teams_list',
            'settings_teams_new',
            'settings_teams_finish',
            'settings_teams_add_agents',
            'settings_teams_show',
            'settings_teams_edit',
            'settings_teams_edit_members',
            'settings_teams_edit_finish',
          ],
          to: accountScopedRoute('settings_teams_list'),
        },
        ...(hasAdvancedAssignment.value
          ? [
              {
                name: 'Settings Agent Assignment',
                label: t('SIDEBAR.AGENT_ASSIGNMENT'),
                icon: 'i-lucide-user-cog',
                activeOn: [
                  'assignment_policy_index',
                  'agent_assignment_policy_index',
                  'agent_assignment_policy_create',
                  'agent_assignment_policy_edit',
                  'agent_capacity_policy_index',
                  'agent_capacity_policy_create',
                  'agent_capacity_policy_edit',
                ],
                to: accountScopedRoute('assignment_policy_index'),
              },
            ]
          : []),
        {
          name: 'Settings Inboxes',
          label: t('SIDEBAR.INBOXES'),
          icon: 'i-lucide-inbox',
          activeOn: [
            'settings_inbox_list',
            'settings_inbox_show',
            'settings_inbox_new',
            'settings_inbox_finish',
            'settings_inboxes_page_channel',
            'settings_inboxes_add_agents',
          ],
          to: accountScopedRoute('settings_inbox_list'),
        },
        {
          name: 'Settings Labels',
          label: t('SIDEBAR.LABELS'),
          icon: 'i-lucide-tags',
          to: accountScopedRoute('labels_list'),
        },
        // Phase H.10 item 6: Custom Attributes / Agent Bots / Macros hidden.
        // Routes still registered; only sidebar entries removed.
        {
          name: 'Settings Automation',
          label: t('SIDEBAR.AUTOMATION'),
          icon: 'i-lucide-repeat',
          to: accountScopedRoute('automation_list'),
        },
        {
          name: 'Settings Canned Responses',
          label: t('SIDEBAR.CANNED_RESPONSES'),
          icon: 'i-lucide-message-square-quote',
          to: accountScopedRoute('canned_list'),
        },
        // Phase H.10: Integrations hub hidden — Patra uses dedicated sidebar entries
        // (Payment Handles, Games, AI Training, Notifications). Routes stay registered.
        {
          name: 'Settings Payment Handles',
          label: t('PAYMENT_HANDLES.NAV_LABEL'),
          icon: 'i-lucide-wallet',
          to: accountScopedUrl('settings/integrations/payment_handles'),
          activeOn: ['settings_integrations_payment_handles'],
        },
        {
          name: 'Settings Games',
          label: t('GAMES.NAV_LABEL'),
          icon: 'i-lucide-gamepad-2',
          to: accountScopedRoute('settings_integrations_games'),
          activeOn: ['settings_integrations_games'],
        },
        {
          name: 'Settings Game Rules',
          label: t('PATRA.SETTINGS.NAV_GAME_RULES'),
          icon: 'i-lucide-scroll-text',
          to: accountScopedRoute('settings_game_rules'),
          activeOn: ['settings_game_rules'],
        },
        {
          name: 'Settings Player Tiers',
          label: t('PATRA.SETTINGS.NAV_PLAYER_TIERS'),
          icon: 'i-lucide-layers',
          to: accountScopedRoute('settings_player_tiers'),
          activeOn: ['settings_player_tiers'],
        },
        {
          name: 'Settings Referrals',
          label: t('PATRA.SETTINGS.NAV_REFERRALS'),
          icon: 'i-lucide-user-plus',
          to: accountScopedRoute('settings_referrals'),
          activeOn: ['settings_referrals'],
        },
        {
          name: 'Settings Reply Style',
          label: t('PATRA.SETTINGS.NAV_REPLY_STYLE'),
          icon: 'i-lucide-message-circle',
          to: accountScopedRoute('settings_reply_style'),
          activeOn: ['settings_reply_style'],
        },
        {
          name: 'Settings Automation Safety',
          label: t('PATRA.SETTINGS.NAV_AUTOMATION_SAFETY'),
          icon: 'i-lucide-shield-check',
          to: accountScopedRoute('settings_automation_safety'),
          activeOn: ['settings_automation_safety'],
        },
        {
          name: 'Settings AI Training',
          label: t('PATRA.SETTINGS.NAV_AI_TRAINING'),
          icon: 'i-lucide-brain',
          to: accountScopedRoute('patra_ai_training'),
          activeOn: ['patra_ai_training'],
        },
        {
          name: 'Settings Notifications',
          label: t('NOTIFICATIONS.NAV_LABEL'),
          icon: 'i-lucide-bell',
          to: accountScopedRoute('settings_integrations_notifications'),
          activeOn: ['settings_integrations_notifications'],
        },
        // Phase H.10 item 6: Audit Logs / Custom Roles / SLA / Conversation
        // Workflow / Security hidden. Routes still registered.
        {
          name: 'Settings Billing',
          label: t('SIDEBAR.BILLING'),
          icon: 'i-lucide-credit-card',
          to: accountScopedRoute('billing_settings_index'),
        },
      ],
    },
  ];
});
</script>

<template>
  <aside
    v-on-click-outside="[
      closeMobileSidebar,
      {
        ignore: [
          '#mobile-sidebar-launcher',
          '[data-popover-content]',
          '[data-popover-backdrop]',
        ],
      },
    ]"
    class="pat-rail patra-nav-rail bg-n-background flex flex-col text-sm pb-px fixed top-0 ltr:left-0 rtl:right-0 h-full z-40 w-[200px] md:w-auto md:relative md:flex-shrink-0 md:ltr:translate-x-0 md:rtl:translate-x-0 ltr:border-r rtl:border-l border-n-weak"
    :class="[
      {
        'shadow-lg md:shadow-none': isMobileSidebarOpen,
        'ltr:-translate-x-full rtl:translate-x-full': !isMobileSidebarOpen,
        'transition-transform duration-200 ease-out md:transition-[width]':
          !isResizing,
      },
    ]"
    :style="isMobile ? undefined : { width: `${sidebarWidth}px` }"
  >
    <section
      class="grid"
      :class="isEffectivelyCollapsed ? 'mt-3 mb-6 gap-4' : 'mt-1 mb-4 gap-2'"
    >
      <div
        class="flex gap-2 items-center min-w-0"
        :class="{
          'justify-center px-1': isEffectivelyCollapsed,
          'px-2': !isEffectivelyCollapsed,
        }"
      >
        <template v-if="isEffectivelyCollapsed">
          <div class="pat-rail-logo">
            <SidebarAccountSwitcher
              is-collapsed
              @show-create-account-modal="emit('showCreateAccountModal')"
            />
          </div>
        </template>
        <template v-else>
          <div class="grid flex-shrink-0 place-content-center size-6">
            <Logo class="size-4" />
          </div>
          <div class="flex-shrink-0 w-px h-3 bg-n-strong" />
          <SidebarAccountSwitcher
            class="flex-grow -mx-1 min-w-0"
            @show-create-account-modal="emit('showCreateAccountModal')"
          />
        </template>
      </div>
      <div
        class="flex gap-2"
        :class="isEffectivelyCollapsed ? 'flex-col items-center' : 'px-2'"
      >
        <RouterLink
          v-if="!isEffectivelyCollapsed"
          :to="{ name: 'search' }"
          class="flex gap-2 items-center px-2 py-1 w-full h-7 rounded-lg outline outline-1 outline-n-weak bg-n-button-color transition-all duration-100 ease-out"
        >
          <span class="flex-shrink-0 i-lucide-search size-4 text-n-slate-10" />
          <span class="flex-grow text-start text-n-slate-10">
            {{ t('COMBOBOX.SEARCH_PLACEHOLDER') }}
          </span>
          <span
            class="hidden tracking-wide pointer-events-none select-none text-n-slate-10"
          >
            {{ searchShortcut }}
          </span>
        </RouterLink>
        <RouterLink
          v-else
          :to="{ name: 'search' }"
          class="pat-rail-item flex items-center justify-center size-8 rounded-lg outline outline-1 outline-n-weak bg-n-button-color transition-all duration-100 ease-out hover:bg-n-alpha-2 dark:hover:bg-n-slate-9/30"
          :title="t('COMBOBOX.SEARCH_PLACEHOLDER')"
        >
          <span class="i-lucide-search size-4 text-n-slate-11" />
        </RouterLink>
        <ComposeConversation align="start">
          <template #trigger="{ isOpen }">
            <Button
              icon="i-lucide-pen-line"
              color="slate"
              size="sm"
              class="dark:hover:!bg-n-slate-9/30"
              :class="[
                isEffectivelyCollapsed
                  ? 'pat-rail-item !size-8 !outline-n-weak !text-n-slate-11'
                  : '!h-7 !outline-n-weak !text-n-slate-11',
                { '!bg-n-alpha-2 dark:!bg-n-slate-9/30': isOpen },
              ]"
            />
          </template>
        </ComposeConversation>
      </div>
    </section>
    <SidebarQuickStats v-if="!isEffectivelyCollapsed" />
    <nav
      class="grid overflow-y-scroll flex-grow gap-2 pb-5 no-scrollbar min-w-0"
      :class="isEffectivelyCollapsed ? 'px-1' : 'px-2'"
    >
      <ul
        class="flex flex-col gap-1 m-0 list-none min-w-0"
        :class="{ 'items-center': isEffectivelyCollapsed }"
      >
        <SidebarGroup
          v-for="item in menuItems"
          :key="item.name"
          v-bind="item"
        />
      </ul>
    </nav>
    <section
      class="flex relative flex-col flex-shrink-0 gap-1 justify-between items-center"
    >
      <div
        class="pointer-events-none absolute inset-x-0 -top-[1.938rem] h-8 bg-gradient-to-t from-n-background to-transparent"
      />
      <SidebarChangelogCard
        v-if="
          isOnChatwootCloud &&
          !isACustomBrandedInstance &&
          !isEffectivelyCollapsed
        "
      />
      <SidebarChangelogButton
        v-if="
          isOnChatwootCloud &&
          !isACustomBrandedInstance &&
          isEffectivelyCollapsed
        "
      />
      <div
        class="px-1 py-1.5 flex-shrink-0 flex w-full z-50 gap-2 items-center border-t border-n-weak shadow-[0px_-2px_4px_0px_rgba(27,28,29,0.02)]"
        :class="isEffectivelyCollapsed ? 'justify-center' : 'justify-between'"
      >
        <div class="pat-rail-avatar">
          <SidebarProfileMenu
            :is-collapsed="isEffectivelyCollapsed"
            @open-key-shortcut-modal="emit('openKeyShortcutModal')"
          />
        </div>
      </div>
    </section>
    <!-- Resize Handle (desktop only) -->
    <div
      class="hidden md:block absolute top-0 h-full w-1 cursor-col-resize z-40 ltr:right-0 rtl:left-0 group"
      @mousedown="onResizeStart"
      @touchstart="onResizeStart"
      @dblclick="onResizeHandleDoubleClick"
    >
      <div
        class="absolute top-0 h-full w-px ltr:right-0 rtl:left-0 bg-transparent group-hover:bg-n-brand transition-colors"
        :class="{ 'bg-n-brand': isResizing }"
      />
    </div>
  </aside>
</template>

<style>
@media (min-width: 768px) {
  /* ── v6 Rail tokens + class layer (pat-rail-*) ── */
  .pat-rail.patra-nav-rail {
    --canvas: #050409;
    --surface: #0c0b12;
    --surface-2: #131119;
    --border: #171520;
    --border-hi: #2e2940;
    --text: #ededf2;
    --text-3: #75727f;
    --patra: #6e56cf;
    --patra-2: #8b5cf6;
    --patra-3: #a78bfa;
    --patra-deep: #5b45b0;
    --patra-glow: rgba(110, 86, 207, 0.55);
    --red: #f85149;
    --green: #3fb950;
  }

  /* A0: block above sets DARK token values on the bare rail class — give the
     tokens light values in light mode so borders/text/icons resolve light. */
  body:not(.dark) .pat-rail.patra-nav-rail,
  [data-theme='light'] .pat-rail.patra-nav-rail {
    --canvas: #f6f5f9;
    --surface: #ffffff;
    --surface-2: #f2f0f7;
    --border: #e5e3eb;
    --border-hi: #d6d3de;
    --text: #1a1a24;
    --text-3: #75727f;
    --patra-glow: rgba(110, 86, 207, 0.28);
  }

  .pat-rail.patra-nav-rail,
  .patra-nav-rail.sidebar-rail,
  .patra-nav-rail.navigation-rails {
    display: flex;
    flex-direction: column;
    align-items: center;
    padding: 14px 0;
    gap: 5px;
    flex-shrink: 0;
    border-right: 1px solid var(--border, #171520);
    background: linear-gradient(
      180deg,
      var(--surface, #0c0b12),
      var(--canvas, #050409)
    );
  }

  .pat-rail-logo,
  .patra-nav-rail .pat-rail-logo,
  .patra-nav-rail .sidebar-logo {
    width: 40px;
    height: 40px;
    border-radius: 12px;
    background: linear-gradient(
      135deg,
      var(--patra, #6e56cf),
      var(--patra-deep, #5b45b0)
    );
    display: flex;
    align-items: center;
    justify-content: center;
    font-family: 'Space Grotesk', sans-serif;
    font-weight: 700;
    color: #fff;
    font-size: 21px;
    box-shadow:
      0 0 22px var(--patra-glow, rgba(110, 86, 207, 0.55)),
      inset 0 1px 0 rgba(255, 255, 255, 0.25);
    margin-bottom: 14px;
    cursor: pointer;
    /* V5 P3: pulse moved to an opacity-animated ::before — animating
       box-shadow repainted the tile every frame, forever. */
    /* 2b: NO transform/transition on this wrapper — the account-switcher
       dropdown renders inside it, and a transform makes the wrapper the
       containing block + stacking context that clips/traps the panel.
       The hover effect lives on the trigger button below instead. */
    position: relative;
  }

  .pat-rail-logo::before,
  .patra-nav-rail .pat-rail-logo::before,
  .patra-nav-rail .sidebar-logo::before {
    content: '';
    position: absolute;
    inset: 0;
    border-radius: inherit;
    box-shadow: 0 0 38px var(--patra-glow, rgba(110, 86, 207, 0.55));
    opacity: 0;
    pointer-events: none;
    animation: logoPulseGlow 4s ease-in-out infinite;
  }

  /* A6: the CSS used to draw its own 'P' (content:'P') on top of the real
     PNG logo tile rendered by Logo.vue inside the account switcher — double
     render. The PNG is the single source of truth; it fills the tile. */
  .pat-rail-logo img {
    width: 100% !important;
    height: 100% !important;
    border-radius: inherit;
  }

  .pat-rail-logo button:hover {
    transform: scale(1.06) rotate(-3deg);
  }

  .pat-rail-logo button {
    transition: transform 0.2s;
    width: 100% !important;
    height: 100% !important;
    min-width: 0 !important;
    min-height: 0 !important;
    padding: 0 !important;
    margin: 0 !important;
    background: transparent !important;
    border: none !important;
    border-radius: inherit !important;
    box-shadow: none !important;
  }

  .pat-rail-logo button::after {
    content: none;
  }

  .pat-rail-logo svg {
    display: none !important;
  }

  /* V5 P3: opacity-only pulse (compositor) — the base 22px glow stays static
     on the tile; this fades the wider 38px glow in and out on the ::before. */
  @keyframes logoPulseGlow {
    0%,
    100% {
      opacity: 0;
    }
    50% {
      opacity: 1;
    }
  }

  .pat-rail-item,
  .patra-nav-rail nav .snav-item {
    width: 44px;
    height: 44px;
    border-radius: 12px;
    display: flex;
    align-items: center;
    justify-content: center;
    color: var(--text-3, #75727f);
    cursor: pointer;
    transition: all 0.25s cubic-bezier(0.34, 1.56, 0.64, 1);
    position: relative;
  }

  .pat-rail-item svg,
  .patra-nav-rail nav .snav-item svg,
  .patra-nav-rail nav .snav-item svg {
    width: 21px;
    height: 21px;
    transition: transform 0.25s;
  }

  .pat-rail-item:hover,
  .patra-nav-rail nav .snav-item:hover {
    color: var(--text, #ededf2);
    background: var(--surface-2, #131119);
    transform: translateY(-2px);
  }

  .pat-rail-item:hover svg,
  .pat-rail-item:hover svg,
  .patra-nav-rail nav .snav-item:hover svg {
    transform: scale(1.1);
  }

  .pat-rail-item.active,
  .patra-nav-rail nav .snav-item.active {
    color: #fff;
    background: linear-gradient(
      135deg,
      var(--patra, #6e56cf),
      var(--patra-deep, #5b45b0)
    );
    box-shadow:
      0 6px 18px var(--patra-glow, rgba(110, 86, 207, 0.55)),
      inset 0 1px 0 rgba(255, 255, 255, 0.2);
  }

  .pat-rail-item.active::before,
  .patra-nav-rail nav .snav-item.active::before {
    content: '';
    position: absolute;
    left: -14px;
    top: 50%;
    transform: translateY(-50%);
    width: 3px;
    height: 22px;
    background: linear-gradient(
      180deg,
      var(--patra-2, #8b5cf6),
      var(--patra-3, #a78bfa)
    );
    border-radius: 0 3px 3px 0;
    box-shadow: 0 0 8px var(--patra-glow, rgba(110, 86, 207, 0.55));
  }

  .pat-rail-badge,
  .patra-nav-rail nav .pat-rail-item .bg-n-brand.absolute,
  .patra-nav-rail nav li .size-2.bg-n-brand {
    position: absolute;
    top: 5px;
    right: 5px;
    min-width: 17px;
    height: 17px;
    padding: 0 4px;
    border-radius: 9px;
    background: var(--red, #f85149) !important;
    color: #fff !important;
    font-size: 9px;
    font-weight: 700;
    display: flex;
    align-items: center;
    justify-content: center;
    border: 2px solid var(--surface, #0c0b12);
  }

  .pat-rail-avatar,
  .patra-nav-rail .pat-rail-avatar {
    position: relative;
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .pat-rail-avatar button {
    width: 36px !important;
    height: 36px !important;
    min-width: 36px !important;
    min-height: 36px !important;
    padding: 0 !important;
    border-radius: 50% !important;
    background: transparent !important;
    border: 2px solid var(--border-hi, #2e2940) !important;
    transition: all 0.2s;
    position: relative;
  }

  .pat-rail-avatar button:hover {
    transform: scale(1.08);
    box-shadow: 0 0 16px var(--patra-glow, rgba(110, 86, 207, 0.55));
  }

  .pat-rail-avatar span.relative.inline-flex {
    width: 32px !important;
    height: 32px !important;
  }

  .pat-rail-avatar .absolute.z-20.border.rounded-full,
  .pat-rail-avatar .online-dot {
    position: absolute;
    bottom: -1px;
    right: -1px;
    width: 11px !important;
    height: 11px !important;
    border-radius: 50%;
    background: var(--green, #3fb950) !important;
    border: 2px solid var(--surface, #0c0b12) !important;
  }

  /* ── legacy patra-nav-rail structural overrides (keep until verified) ── */
  .patra-nav-rail {
    width: 66px !important;
    min-width: 66px !important;
    max-width: 66px !important;
    flex: 0 0 66px !important;
    background: linear-gradient(
      180deg,
      var(--patra-surface, #0c0b12),
      var(--patra-canvas, #050409)
    ) !important;
    border-color: var(--patra-border, #171520) !important;
    padding: 14px 0 !important;
    gap: 8px !important;
    align-items: center !important;
  }

  .patra-nav-rail > div.absolute {
    display: none !important;
  }

  .patra-nav-rail > section:first-child {
    display: flex !important;
    flex-direction: column !important;
    align-items: center !important;
    width: 100% !important;
    margin: 0 !important;
    padding: 0 !important;
    gap: 8px !important;
  }

  .patra-nav-rail > section:first-child > div:first-child {
    justify-content: center !important;
    padding: 0 !important;
    width: 100% !important;
  }

  .patra-nav-rail > section:first-child .flex-shrink-0.w-px,
  .patra-nav-rail #sidebar-account-switcher,
  .patra-nav-rail > section:first-child > div:first-child > button span,
  .patra-nav-rail > section:first-child .pat-rail-logo button span,
  .patra-nav-rail
    > section:first-child
    > div:first-child
    > button
    .i-lucide-chevron-down,
  .patra-nav-rail > section:first-child .pat-rail-logo .i-lucide-chevron-down {
    display: none !important;
  }

  .patra-nav-rail > section:first-child .size-6,
  .patra-nav-rail > section:first-child .pat-rail-logo,
  .patra-nav-rail > section:first-child button:has(.size-7) {
    width: 40px !important;
    height: 40px !important;
    min-width: 40px !important;
    min-height: 40px !important;
    border-radius: 12px !important;
    background: linear-gradient(135deg, #6e56cf, #5b45b0) !important;
    display: flex !important;
    align-items: center !important;
    justify-content: center !important;
    padding: 0 !important;
    cursor: pointer !important;
    transition: transform 0.2s !important;
  }

  .patra-nav-rail > section:first-child .size-6 svg,
  .patra-nav-rail > section:first-child .pat-rail-logo svg,
  .patra-nav-rail > section:first-child button:has(.size-7) svg {
    display: none !important;
  }

  /* A6: PNG logo fills the forced 40px tile in both collapsed + expanded */
  .patra-nav-rail > section:first-child .size-6 img,
  .patra-nav-rail > section:first-child button:has(.size-7) img {
    width: 100% !important;
    height: 100% !important;
    border-radius: 12px;
  }

  .patra-nav-rail > section:first-child .size-6::after,
  .patra-nav-rail > section:first-child button:has(.size-7)::after {
    content: none;
  }

  .patra-nav-rail > section:last-child .pat-rail-avatar {
    width: 100%;
    display: flex;
    justify-content: center;
  }

  .patra-nav-rail > section:first-child > div:last-child {
    flex-direction: column !important;
    align-items: center !important;
    padding: 0 !important;
    gap: 8px !important;
    width: 100% !important;
  }

  .patra-nav-rail > section:first-child a,
  .patra-nav-rail > section:first-child button {
    width: 44px !important;
    height: 44px !important;
    min-width: 44px !important;
    min-height: 44px !important;
    padding: 0 !important;
    justify-content: center !important;
    outline: none !important;
    border-radius: 12px !important;
  }

  .patra-nav-rail > section:first-child a span:not([class*='i-lucide']),
  .patra-nav-rail > section:first-child a .flex-grow {
    display: none !important;
  }

  .patra-nav-rail > div.grid-cols-3 {
    display: none !important;
  }

  .patra-nav-rail > nav {
    width: 100% !important;
    padding: 0 !important;
    display: flex !important;
    flex-direction: column !important;
    align-items: center !important;
    gap: 8px !important;
  }

  .patra-nav-rail > nav ul {
    align-items: center !important;
    gap: 8px !important;
    width: 100% !important;
    padding: 0 !important;
  }

  .patra-nav-rail .sidebar-group-children,
  .patra-nav-rail .snav-group,
  .patra-nav-rail .snav-title {
    display: none !important;
  }

  .patra-nav-rail nav li > div > a,
  .patra-nav-rail nav li > div > button,
  .patra-nav-rail nav li > a,
  .patra-nav-rail nav li > button,
  .patra-nav-rail nav .pat-rail-item,
  .patra-nav-rail nav .snav-item,
  .patra-nav-rail nav [role='button'] {
    width: 44px !important;
    height: 44px !important;
    min-width: 44px !important;
    min-height: 44px !important;
    border-radius: 12px !important;
    display: flex !important;
    align-items: center !important;
    justify-content: center !important;
    color: var(--patra-text-3, #54515e) !important;
    background: transparent !important;
    box-shadow: none !important;
    position: relative !important;
    transition: all 0.2s !important;
    padding: 0 !important;
    margin: 0 auto !important;
  }

  .patra-nav-rail nav li span.truncate,
  .patra-nav-rail nav li .flex-grow span,
  .patra-nav-rail nav li .text-body-main,
  .patra-nav-rail nav .snav-item span,
  .patra-nav-rail nav .i-lucide-chevron-up {
    display: none !important;
  }

  .patra-nav-rail nav li > div > a:hover,
  .patra-nav-rail nav li > div > button:hover,
  .patra-nav-rail nav li > a:hover,
  .patra-nav-rail nav li > button:hover,
  .patra-nav-rail nav .pat-rail-item:hover,
  .patra-nav-rail nav .snav-item:hover {
    color: var(--patra-text, #ededf2) !important;
    background: var(--patra-surface-2, #131119) !important;
    transform: translateY(-2px) !important;
  }

  .patra-nav-rail nav li > div > a.text-n-slate-12,
  .patra-nav-rail nav li > div > button.text-n-slate-12,
  .patra-nav-rail nav li > div > button.font-medium.text-n-slate-12,
  .patra-nav-rail nav li > a.text-n-slate-12,
  .patra-nav-rail nav li > button.text-n-slate-12,
  .patra-nav-rail nav li > a.router-link-active,
  .patra-nav-rail nav .pat-rail-item.active,
  .patra-nav-rail nav .snav-item.active {
    color: #fff !important;
    background: linear-gradient(135deg, #6e56cf, #5b45b0) !important;
    box-shadow: 0 4px 14px rgba(110, 86, 207, 0.35) !important;
  }

  .patra-nav-rail nav li > div > a.text-n-slate-12::before,
  .patra-nav-rail nav li > div > button.text-n-slate-12::before,
  .patra-nav-rail nav li > div > button.font-medium.text-n-slate-12::before,
  .patra-nav-rail nav li > a.text-n-slate-12::before,
  .patra-nav-rail nav li > button.text-n-slate-12::before,
  .patra-nav-rail nav li > a.router-link-active::before,
  .patra-nav-rail nav .pat-rail-item.active::before,
  .patra-nav-rail nav .snav-item.active::before {
    content: '';
    position: absolute;
    left: -14px;
    top: 50%;
    transform: translateY(-50%);
    width: 3px;
    height: 20px;
    background: #6e56cf;
    border-radius: 0 3px 3px 0;
  }

  .patra-nav-rail nav [title]:hover::after {
    content: attr(title);
    position: absolute;
    left: calc(100% + 12px);
    top: 50%;
    transform: translateY(-50%);
    background: var(--patra-surface-2, #131119);
    border: 1px solid var(--patra-border-hi, #2e2940);
    color: var(--patra-text, #ededf2);
    font-size: 12px;
    font-weight: 500;
    padding: 5px 10px;
    border-radius: 8px;
    white-space: nowrap;
    pointer-events: none;
    z-index: 100;
  }

  .patra-nav-rail > section:last-child {
    width: 100% !important;
    align-items: center !important;
    padding: 0 !important;
    border: none !important;
    box-shadow: none !important;
  }

  .patra-nav-rail > section:last-child > div:first-child,
  .patra-nav-rail > section:last-child > :not(:last-child) {
    display: none !important;
  }

  .patra-nav-rail > section:last-child > div:last-child {
    justify-content: center !important;
    border: none !important;
    box-shadow: none !important;
    padding: 0 !important;
    width: 100% !important;
  }

  .patra-nav-rail > section:last-child button .min-w-0 {
    display: none !important;
  }

  .patra-nav-rail > section:last-child button {
    width: 44px !important;
    height: 44px !important;
    padding: 0 !important;
    justify-content: center !important;
    border-radius: 12px !important;
  }
}
</style>
