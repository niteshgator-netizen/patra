<script setup>
import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';

const { accountScopedRoute } = useAccount();
const currentRole = useMapGetter('getCurrentRole');
const isAdmin = computed(() => currentRole.value === 'administrator');

// Featured card on top, then grouped cards. adminOnly cards hide for agents
// (their target routes require the administrator/report_manage permission).
const featured = {
  label: 'Sweepstakes Reports',
  description:
    'Loads, cashouts, and freeplay across your games — the daily numbers.',
  icon: 'i-lucide-chart-spline',
  route: 'patra_reports',
};

const groups = computed(() =>
  [
    {
      title: 'Sweepstakes',
      cards: [
        {
          label: 'Owner Live Overview',
          description:
            'Live pulse of the whole operation — open conversations, agent status, traffic.',
          icon: 'i-lucide-activity',
          route: 'account_overview_reports',
          adminOnly: true,
        },
        {
          label: 'Agent Leaderboard',
          description: 'Who is handling the most chats, ranked.',
          icon: 'i-lucide-trophy',
          route: 'patra_leaderboard',
        },
        {
          label: 'Sweeps Financial',
          description: 'Deposits vs cashouts per game — the money picture.',
          icon: 'i-lucide-banknote',
          route: 'patra_sweeps_report',
          adminOnly: true,
        },
      ],
    },
    {
      title: 'Support quality',
      cards: [
        {
          label: 'CSAT',
          description: 'How players rated their chats after the conversation.',
          icon: 'i-lucide-smile',
          route: 'csat_reports',
          adminOnly: true,
        },
        {
          label: 'Agents',
          description:
            'Per-agent workload and response times over any date range.',
          icon: 'i-lucide-square-user',
          route: 'agent_reports',
          adminOnly: true,
        },
        {
          label: 'SLA',
          description:
            'Whether chats got first replies within your time targets.',
          icon: 'i-lucide-timer',
          route: 'sla_reports',
          adminOnly: true,
        },
      ],
    },
    {
      title: 'Volume breakdowns',
      cards: [
        {
          label: 'Conversations',
          description: 'Total chat volume and resolution trends over time.',
          icon: 'i-lucide-message-circle',
          route: 'conversation_reports',
          adminOnly: true,
        },
        {
          label: 'Inboxes',
          description: 'Which channel (FB, Telegram, …) the chats come from.',
          icon: 'i-lucide-inbox',
          route: 'inbox_reports',
          adminOnly: true,
        },
        {
          label: 'Labels',
          description: 'Chat volume split by the labels your team applies.',
          icon: 'i-lucide-tag',
          route: 'label_reports',
          adminOnly: true,
        },
        {
          label: 'Teams',
          description: 'How each team is performing side by side.',
          icon: 'i-lucide-users',
          route: 'team_reports',
          adminOnly: true,
        },
      ],
    },
  ]
    .map(group => ({
      ...group,
      cards: group.cards.filter(card => isAdmin.value || !card.adminOnly),
    }))
    .filter(group => group.cards.length > 0)
);
</script>

<template>
  <div class="flex flex-col gap-6 p-6 overflow-y-auto w-full">
    <header>
      <h2 class="text-2xl font-semibold text-n-slate-12">Reports</h2>
      <p class="text-sm text-n-slate-11">
        Every report in one place. Start with the sweepstakes numbers.
      </p>
    </header>

    <RouterLink
      :to="accountScopedRoute(featured.route)"
      class="flex items-center gap-4 rounded-xl border border-n-weak bg-n-solid-1 p-5 transition-colors hover:border-n-strong"
    >
      <span
        class="flex size-12 flex-shrink-0 items-center justify-center rounded-xl bg-n-brand/10"
      >
        <span :class="featured.icon" class="size-6 text-n-brand" />
      </span>
      <span class="flex flex-col min-w-0">
        <span class="text-base font-semibold text-n-slate-12">
          {{ featured.label }}
        </span>
        <span class="text-sm text-n-slate-11">{{ featured.description }}</span>
      </span>
      <span
        class="i-lucide-arrow-right ml-auto size-4 flex-shrink-0 text-n-slate-10"
      />
    </RouterLink>

    <section v-for="group in groups" :key="group.title">
      <h3
        class="mb-2 text-xs font-semibold uppercase tracking-wide text-n-slate-10"
      >
        {{ group.title }}
      </h3>
      <div class="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
        <RouterLink
          v-for="card in group.cards"
          :key="card.route"
          :to="accountScopedRoute(card.route)"
          class="flex items-start gap-3 rounded-xl border border-n-weak bg-n-solid-1 p-4 transition-colors hover:border-n-strong"
        >
          <span
            class="mt-0.5 flex size-8 flex-shrink-0 items-center justify-center rounded-lg bg-n-alpha-2"
          >
            <span :class="card.icon" class="size-4 text-n-slate-11" />
          </span>
          <span class="flex flex-col min-w-0">
            <span class="text-sm font-medium text-n-slate-12">
              {{ card.label }}
            </span>
            <span class="text-xs text-n-slate-11">{{ card.description }}</span>
          </span>
        </RouterLink>
      </div>
    </section>
  </div>
</template>
