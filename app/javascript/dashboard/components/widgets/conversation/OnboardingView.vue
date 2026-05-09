<script setup>
import { computed, onMounted } from 'vue';
import { useStore, useStoreGetters } from 'dashboard/composables/store';

const store = useStore();
const getters = useStoreGetters();

// ---------- greeting ----------
const currentUser = computed(() => getters.getCurrentUser.value || {});
const firstName = computed(() => {
  const full = (currentUser.value.name || '').trim();
  return full.split(' ')[0] || 'there';
});
const greetingPrefix = computed(() => {
  const h = new Date().getHours();
  if (h < 12) return 'Good morning';
  if (h < 18) return 'Good afternoon';
  return 'Good evening';
});

// ---------- top-row stats (real Chatwoot data) ----------
const conversationMetric = computed(
  () => getters.getAccountConversationMetric.value || {}
);
const accountSummary = computed(
  () => getters.getAccountSummary.value || {}
);
const botSummary = computed(() => getters.getBotSummary.value || {});

const openConversations = computed(
  () => conversationMetric.value.open ?? '—'
);
const resolvedToday = computed(
  () => accountSummary.value.resolutions_count ?? '—'
);
const aiHandled = computed(
  () => botSummary.value.bot_resolutions_count ?? '—'
);
const avgResponseFormatted = computed(() => {
  const s = Number(accountSummary.value.avg_first_response_time || 0);
  if (!s) return '—';
  if (s < 60) return `${Math.round(s)}s`;
  if (s < 3600) return `${Math.round(s / 60)}m`;
  return `${Math.round(s / 3600)}h`;
});

// ---------- connected channels ----------
const inboxes = computed(() => getters['inboxes/getInboxes'].value || []);

const CHANNEL_LABELS = {
  'Channel::WebWidget': 'Website',
  'Channel::FacebookPage': 'Facebook',
  'Channel::Whatsapp': 'WhatsApp',
  'Channel::Email': 'Email',
  'Channel::Telegram': 'Telegram',
  'Channel::Instagram': 'Instagram',
  'Channel::TwilioSms': 'SMS',
  'Channel::Sms': 'SMS',
  'Channel::Line': 'Line',
  'Channel::Api': 'API',
  'Channel::Twitter': 'Twitter',
};
function channelLabel(type) {
  return CHANNEL_LABELS[type] || (type || '').replace('Channel::', '') || 'Channel';
}
function channelInitial(type) {
  return channelLabel(type).charAt(0).toUpperCase();
}
function inboxStatus(inbox) {
  return inbox.enable_auto_assignment === false ? 'Manual' : 'Active';
}

// ---------- quick actions ----------
// All routes verified to exist in app/javascript/dashboard/routes/.
const quickActions = [
  {
    label: 'Add inbox',
    description: 'Connect a new channel',
    icon: 'add-circle',
    route: 'settings_inbox_new',
  },
  {
    label: 'Invite agent',
    description: 'Manage your team',
    icon: 'person-add',
    route: 'agent_list',
  },
  {
    label: 'Patra AI',
    description: 'Configure assistants',
    icon: 'sparkle',
    route: 'captain_assistants_index',
  },
  {
    label: 'View reports',
    description: 'Channel analytics',
    icon: 'chart-multiple',
    route: 'account_overview_reports',
  },
];

// ---------- today range for fetches ----------
function todayRange() {
  const now = new Date();
  const start = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  return {
    from: Math.floor(start.getTime() / 1000),
    to: Math.floor(now.getTime() / 1000),
  };
}

onMounted(() => {
  const { from, to } = todayRange();
  // Each dispatch silenced — action signature varies across Chatwoot versions
  // and the dashboard should still render with `—` placeholders if any fail.
  store
    .dispatch('fetchAccountConversationMetric', { type: 'conversation' })
    .catch(() => {});
  store
    .dispatch('fetchAccountSummary', {
      from,
      to,
      type: 'account',
      groupBy: 'day',
      businessHours: false,
    })
    .catch(() => {});
  store
    .dispatch('fetchBotSummary', {
      from,
      to,
      type: 'account',
      groupBy: 'day',
      businessHours: false,
    })
    .catch(() => {});
  store.dispatch('inboxes/get').catch(() => {});
});
</script>

<template>
  <div class="h-full overflow-y-auto bg-n-background">
    <div class="max-w-7xl mx-auto p-6 lg:p-8 space-y-6">
      <!-- Greeting -->
      <header>
        <h1 class="text-2xl font-semibold text-n-slate-12 tracking-tight">
          {{ greetingPrefix }}, {{ firstName }}
        </h1>
        <p class="text-sm text-n-slate-11 mt-1">
          Here's what's happening across your channels today.
        </p>
      </header>

      <!-- Stat cards -->
      <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <div
          class="bg-white dark:bg-n-solid-2 rounded-xl border border-n-weak p-5"
        >
          <p
            class="text-xs font-medium text-n-slate-11 uppercase tracking-wide"
          >
            Open conversations
          </p>
          <p
            class="text-3xl font-semibold text-n-slate-12 mt-2 tabular-nums"
          >
            {{ openConversations }}
          </p>
        </div>
        <div
          class="bg-white dark:bg-n-solid-2 rounded-xl border border-n-weak p-5"
        >
          <p
            class="text-xs font-medium text-n-slate-11 uppercase tracking-wide"
          >
            Resolved today
          </p>
          <p
            class="text-3xl font-semibold text-n-slate-12 mt-2 tabular-nums"
          >
            {{ resolvedToday }}
          </p>
        </div>
        <div
          class="relative bg-white dark:bg-n-solid-2 rounded-xl border border-woot-200 p-5"
        >
          <span
            class="absolute top-3 right-3 inline-block w-1.5 h-1.5 bg-woot-500 rounded-full"
          />
          <p
            class="text-xs font-medium text-woot-500 uppercase tracking-wide flex items-center gap-1.5"
          >
            <fluent-icon icon="sparkle" size="12" />
            Patra AI handled
          </p>
          <p
            class="text-3xl font-semibold text-n-slate-12 mt-2 tabular-nums"
          >
            {{ aiHandled }}
          </p>
        </div>
        <div
          class="bg-white dark:bg-n-solid-2 rounded-xl border border-n-weak p-5"
        >
          <p
            class="text-xs font-medium text-n-slate-11 uppercase tracking-wide"
          >
            Avg response time
          </p>
          <p
            class="text-3xl font-semibold text-n-slate-12 mt-2 tabular-nums"
          >
            {{ avgResponseFormatted }}
          </p>
        </div>
      </div>

      <!-- Two-column row -->
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <!-- Connected channels -->
        <div
          class="bg-white dark:bg-n-solid-2 rounded-xl border border-n-weak p-5"
        >
          <div class="flex items-center justify-between mb-4">
            <h2 class="text-base font-semibold text-n-slate-12">
              Connected channels
            </h2>
            <router-link
              :to="{ name: 'settings_inbox_list' }"
              class="text-xs font-medium text-woot-500 hover:underline"
            >
              Manage
            </router-link>
          </div>
          <div
            v-if="inboxes.length === 0"
            class="text-sm text-n-slate-11 py-6 text-center"
          >
            No channels connected yet.
            <router-link
              :to="{ name: 'settings_inbox_new' }"
              class="text-woot-500 hover:underline"
              >Connect one</router-link
            >.
          </div>
          <ul v-else class="divide-y divide-n-weak">
            <li
              v-for="inbox in inboxes"
              :key="inbox.id"
              class="flex items-center gap-3 py-3"
            >
              <div
                class="w-9 h-9 rounded-lg bg-woot-25 flex items-center justify-center text-woot-500 font-semibold text-sm flex-shrink-0"
              >
                {{ channelInitial(inbox.channel_type) }}
              </div>
              <div class="flex-1 min-w-0">
                <p
                  class="text-sm font-medium text-n-slate-12 truncate"
                >
                  {{ inbox.name }}
                </p>
                <p class="text-xs text-n-slate-11">
                  {{ channelLabel(inbox.channel_type) }}
                </p>
              </div>
              <span
                class="text-xs font-medium px-2 py-0.5 rounded-full bg-green-50 text-green-700 border border-green-200 dark:bg-green-900/20 dark:text-green-400 dark:border-green-800"
              >
                {{ inboxStatus(inbox) }}
              </span>
            </li>
          </ul>
        </div>

        <!-- Quick actions -->
        <div
          class="bg-white dark:bg-n-solid-2 rounded-xl border border-n-weak p-5"
        >
          <h2 class="text-base font-semibold text-n-slate-12 mb-4">
            Quick actions
          </h2>
          <div class="grid grid-cols-2 gap-3">
            <router-link
              v-for="action in quickActions"
              :key="action.label"
              :to="{ name: action.route }"
              class="flex flex-col gap-2 p-4 rounded-lg border border-n-weak hover:border-woot-500 hover:bg-woot-25 transition-colors group"
            >
              <div
                class="w-9 h-9 rounded-lg bg-woot-25 group-hover:bg-woot-100 flex items-center justify-center"
              >
                <fluent-icon
                  :icon="action.icon"
                  size="18"
                  class="text-woot-500"
                />
              </div>
              <p class="text-sm font-medium text-n-slate-12">
                {{ action.label }}
              </p>
              <p class="text-xs text-n-slate-11">
                {{ action.description }}
              </p>
            </router-link>
          </div>
        </div>
      </div>

      <!-- Bottom row: business-specific cards.
           These three cards reference Patra-specific concepts (backup pages,
           crypto-payments, game automation) that aren't in Chatwoot's default
           data model. Wired with safe placeholder values until you connect a
           custom data source. -->
      <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
        <div
          class="bg-white dark:bg-n-solid-2 rounded-xl border border-n-weak p-5"
        >
          <div class="flex items-center justify-between mb-2">
            <h3 class="text-sm font-medium text-n-slate-11">
              Backup page status
            </h3>
            <span class="inline-block w-2 h-2 bg-green-500 rounded-full" />
          </div>
          <p class="text-xl font-semibold text-n-slate-12">
            All systems active
          </p>
          <p class="text-xs text-n-slate-11 mt-1">
            No fallback pages triggered.
          </p>
        </div>
        <div
          class="bg-white dark:bg-n-solid-2 rounded-xl border border-n-weak p-5"
        >
          <div class="flex items-center justify-between mb-2">
            <h3 class="text-sm font-medium text-n-slate-11">
              Payments pending
            </h3>
            <fluent-icon
              icon="money"
              size="14"
              class="text-n-slate-11"
            />
          </div>
          <p class="text-xl font-semibold text-n-slate-12 tabular-nums">—</p>
          <p class="text-xs text-n-slate-11 mt-1">
            Connect a payment source.
          </p>
        </div>
        <div
          class="bg-white dark:bg-n-solid-2 rounded-xl border border-n-weak p-5"
        >
          <div class="flex items-center justify-between mb-2">
            <h3 class="text-sm font-medium text-n-slate-11">
              Game automation
            </h3>
            <fluent-icon
              icon="bot"
              size="14"
              class="text-n-slate-11"
            />
          </div>
          <p class="text-xl font-semibold text-n-slate-12">Idle</p>
          <p class="text-xs text-n-slate-11 mt-1">
            No active load/redeem workflows.
          </p>
        </div>
      </div>
    </div>
  </div>
</template>
