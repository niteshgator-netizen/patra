<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import ownerStatsAPI from 'dashboard/api/ownerStats';

const { t } = useI18n();

const loading = ref(true);
const error = ref(false);
const stats = ref(null);

const inverseGrowthKeys = new Set(['avg_response_time_seconds']);

const fetchStats = async () => {
  loading.value = true;
  error.value = false;
  try {
    const { data } = await ownerStatsAPI.show();
    stats.value = data;
  } catch {
    error.value = true;
  } finally {
    loading.value = false;
  }
};

onMounted(() => {
  fetchStats();
});

function formatDurationSeconds(sec) {
  const n = Number(sec);
  if (!Number.isFinite(n) || n <= 0) return '—';
  if (n < 60) return `${Math.round(n)}s`;
  const m = Math.floor(n / 60);
  const s = Math.round(n % 60);
  return s > 0 ? `${m}m ${s}s` : `${m}m`;
}

function formatMoney(amount) {
  const n = Number(amount);
  if (!Number.isFinite(n)) return '0';
  return n.toLocaleString(undefined, { minimumFractionDigits: 0, maximumFractionDigits: 2 });
}

function formatPercent(p) {
  const n = Number(p);
  if (!Number.isFinite(n)) return '0%';
  return `${n}%`;
}

function growthClass(key, value) {
  const v = Number(value);
  if (!Number.isFinite(v) || v === 0) return 'text-n-slate-11';
  const good = v > 0;
  const inverted = inverseGrowthKeys.has(key);
  const isGood = inverted ? !good : good;
  return isGood ? 'text-green-600 dark:text-green-400' : 'text-red-600 dark:text-red-400';
}

function growthLabel(key, value) {
  const v = Number(value);
  if (!Number.isFinite(v)) return '—';
  const sign = v > 0 ? '+' : '';
  return `${sign}${v}%`;
}

const growthRows = computed(() => {
  const g = stats.value?.growth_vs_previous_week;
  if (!g) return [];
  return [
    { key: 'incoming_messages', label: t('OVERVIEW_REPORTS.OWNER_STATS.MESSAGES_RECEIVED'), value: g.incoming_messages },
    { key: 'conversations', label: t('OVERVIEW_REPORTS.OWNER_STATS.CONVERSATIONS'), value: g.conversations },
    { key: 'ai_handle_rate', label: t('OVERVIEW_REPORTS.OWNER_STATS.AI_HANDLE_RATE'), value: g.ai_handle_rate },
    {
      key: 'avg_response_time_seconds',
      label: t('OVERVIEW_REPORTS.OWNER_STATS.AVG_RESPONSE_TIME'),
      value: g.avg_response_time_seconds,
    },
    { key: 'deposits_count', label: t('OVERVIEW_REPORTS.OWNER_STATS.GROWTH_DEPOSITS_COUNT'), value: g.deposits_count },
    { key: 'deposits_total', label: t('OVERVIEW_REPORTS.OWNER_STATS.GROWTH_DEPOSITS_TOTAL'), value: g.deposits_total },
    { key: 'cashouts_count', label: t('OVERVIEW_REPORTS.OWNER_STATS.GROWTH_CASHOUTS_COUNT'), value: g.cashouts_count },
    { key: 'cashouts_total', label: t('OVERVIEW_REPORTS.OWNER_STATS.GROWTH_CASHOUTS_TOTAL'), value: g.cashouts_total },
  ];
});

function statCardTone(labelKey) {
  if (labelKey === 'escalation') return 'border-red-200/80 dark:border-red-900/50 bg-red-50/40 dark:bg-red-950/20';
  if (labelKey === 'ai_rate' || labelKey === 'handle') return 'border-green-200/80 dark:border-green-900/50 bg-green-50/40 dark:bg-green-950/20';
  return 'border-n-weak dark:border-n-slate-6 bg-n-alpha-2';
}
</script>

<template>
  <div class="rounded-xl border border-n-weak dark:border-n-slate-6 bg-n-solid-2 p-4 shadow-sm">
    <div class="mb-4 flex flex-wrap items-start justify-between gap-3">
      <div>
        <h2 class="text-lg font-semibold text-n-slate-12">
          {{ t('OVERVIEW_REPORTS.OWNER_STATS.TITLE') }}
        </h2>
        <p class="text-sm text-n-slate-11">
          {{ t('OVERVIEW_REPORTS.OWNER_STATS.SUBTITLE') }}
        </p>
      </div>
      <button
        type="button"
        class="rounded-lg border border-n-weak bg-n-solid-1 px-3 py-1.5 text-sm font-medium text-n-slate-12 hover:bg-n-alpha-2 dark:border-n-slate-6"
        :disabled="loading"
        @click="fetchStats"
      >
        {{ t('OVERVIEW_REPORTS.OWNER_STATS.REFRESH') }}
      </button>
    </div>

    <div v-if="loading" class="py-12 text-center text-sm text-n-slate-11">
      {{ t('OVERVIEW_REPORTS.OWNER_STATS.LOADING') }}
    </div>
    <div v-else-if="error" class="py-8 text-center text-sm text-red-600 dark:text-red-400">
      {{ t('OVERVIEW_REPORTS.OWNER_STATS.ERROR') }}
    </div>
    <div v-else-if="stats" class="flex flex-col gap-8">
      <section>
        <h3 class="mb-3 text-sm font-semibold uppercase tracking-wide text-n-slate-11">
          {{ t('OVERVIEW_REPORTS.OWNER_STATS.TODAY') }}
        </h3>
        <div class="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
          <div
            class="rounded-lg border p-4"
            :class="statCardTone('default')"
          >
            <p class="text-xs font-medium text-n-slate-11">
              {{ t('OVERVIEW_REPORTS.OWNER_STATS.MESSAGES_RECEIVED') }}
            </p>
            <p class="mt-1 text-3xl font-bold tabular-nums text-n-slate-12">
              {{ stats.today.incoming_messages }}
            </p>
          </div>
          <div class="rounded-lg border border-n-weak p-4 dark:border-n-slate-6">
            <p class="text-xs font-medium text-n-slate-11">
              {{ t('OVERVIEW_REPORTS.OWNER_STATS.CONVERSATIONS') }}
            </p>
            <p class="mt-1 text-3xl font-bold tabular-nums text-n-slate-12">
              {{ stats.today.conversations }}
            </p>
          </div>
          <div
            class="rounded-lg border p-4"
            :class="statCardTone('ai_rate')"
          >
            <p class="text-xs font-medium text-n-slate-11">
              {{ t('OVERVIEW_REPORTS.OWNER_STATS.AI_HANDLE_RATE') }}
            </p>
            <p class="mt-1 text-3xl font-bold tabular-nums text-green-700 dark:text-green-400">
              {{ formatPercent(stats.today.ai_handle_rate) }}
            </p>
            <p class="mt-1 text-xs text-n-slate-11">
              {{ t('OVERVIEW_REPORTS.OWNER_STATS.TOOLTIP_AI_RATE') }}
            </p>
          </div>
          <div class="rounded-lg border border-n-weak p-4 dark:border-n-slate-6">
            <p class="text-xs font-medium text-n-slate-11">
              {{ t('OVERVIEW_REPORTS.OWNER_STATS.AVG_RESPONSE_TIME') }}
            </p>
            <p class="mt-1 text-3xl font-bold tabular-nums text-n-slate-12">
              {{ formatDurationSeconds(stats.today.avg_response_time_seconds) }}
            </p>
          </div>
          <div class="rounded-lg border border-n-weak p-4 dark:border-n-slate-6">
            <p class="text-xs font-medium text-n-slate-11">
              {{ t('OVERVIEW_REPORTS.OWNER_STATS.DEPOSITS') }}
            </p>
            <p class="mt-1 text-2xl font-bold tabular-nums text-n-slate-12">
              {{
                t('OVERVIEW_REPORTS.OWNER_STATS.COUNT_TOTAL', {
                  count: stats.today.deposits.count,
                  total: formatMoney(stats.today.deposits.total),
                })
              }}
            </p>
            <p class="mt-1 text-xs text-n-slate-11">
              {{ t('OVERVIEW_REPORTS.OWNER_STATS.TOOLTIP_FINANCE') }}
            </p>
          </div>
          <div class="rounded-lg border border-n-weak p-4 dark:border-n-slate-6">
            <p class="text-xs font-medium text-n-slate-11">
              {{ t('OVERVIEW_REPORTS.OWNER_STATS.CASHOUTS') }}
            </p>
            <p class="mt-1 text-2xl font-bold tabular-nums text-n-slate-12">
              {{
                t('OVERVIEW_REPORTS.OWNER_STATS.COUNT_TOTAL', {
                  count: stats.today.cashouts.count,
                  total: formatMoney(stats.today.cashouts.total),
                })
              }}
            </p>
          </div>
        </div>
      </section>

      <section>
        <h3 class="mb-3 text-sm font-semibold uppercase tracking-wide text-n-slate-11">
          {{ t('OVERVIEW_REPORTS.OWNER_STATS.THIS_WEEK') }}
        </h3>
        <div class="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
          <div class="rounded-lg border border-n-weak p-4 dark:border-n-slate-6">
            <p class="text-xs font-medium text-n-slate-11">
              {{ t('OVERVIEW_REPORTS.OWNER_STATS.MESSAGES_RECEIVED') }}
            </p>
            <p class="mt-1 text-3xl font-bold tabular-nums text-n-slate-12">
              {{ stats.this_week.incoming_messages }}
            </p>
          </div>
          <div class="rounded-lg border border-n-weak p-4 dark:border-n-slate-6">
            <p class="text-xs font-medium text-n-slate-11">
              {{ t('OVERVIEW_REPORTS.OWNER_STATS.CONVERSATIONS') }}
            </p>
            <p class="mt-1 text-3xl font-bold tabular-nums text-n-slate-12">
              {{ stats.this_week.conversations }}
            </p>
          </div>
          <div
            class="rounded-lg border p-4"
            :class="statCardTone('ai_rate')"
          >
            <p class="text-xs font-medium text-n-slate-11">
              {{ t('OVERVIEW_REPORTS.OWNER_STATS.AI_HANDLE_RATE') }}
            </p>
            <p class="mt-1 text-3xl font-bold tabular-nums text-green-700 dark:text-green-400">
              {{ formatPercent(stats.this_week.ai_handle_rate) }}
            </p>
          </div>
          <div class="rounded-lg border border-n-weak p-4 dark:border-n-slate-6">
            <p class="text-xs font-medium text-n-slate-11">
              {{ t('OVERVIEW_REPORTS.OWNER_STATS.AVG_RESPONSE_TIME') }}
            </p>
            <p class="mt-1 text-3xl font-bold tabular-nums text-n-slate-12">
              {{ formatDurationSeconds(stats.this_week.avg_response_time_seconds) }}
            </p>
          </div>
          <div class="rounded-lg border border-n-weak p-4 dark:border-n-slate-6">
            <p class="text-xs font-medium text-n-slate-11">
              {{ t('OVERVIEW_REPORTS.OWNER_STATS.DEPOSITS') }}
            </p>
            <p class="mt-1 text-2xl font-bold tabular-nums text-n-slate-12">
              {{
                t('OVERVIEW_REPORTS.OWNER_STATS.COUNT_TOTAL', {
                  count: stats.this_week.deposits.count,
                  total: formatMoney(stats.this_week.deposits.total),
                })
              }}
            </p>
          </div>
          <div class="rounded-lg border border-n-weak p-4 dark:border-n-slate-6">
            <p class="text-xs font-medium text-n-slate-11">
              {{ t('OVERVIEW_REPORTS.OWNER_STATS.CASHOUTS') }}
            </p>
            <p class="mt-1 text-2xl font-bold tabular-nums text-n-slate-12">
              {{
                t('OVERVIEW_REPORTS.OWNER_STATS.COUNT_TOTAL', {
                  count: stats.this_week.cashouts.count,
                  total: formatMoney(stats.this_week.cashouts.total),
                })
              }}
            </p>
          </div>
        </div>
      </section>

      <section>
        <h3 class="mb-3 text-sm font-semibold uppercase tracking-wide text-n-slate-11">
          {{ t('OVERVIEW_REPORTS.OWNER_STATS.GROWTH_HEADER') }}
        </h3>
        <div class="grid gap-2 sm:grid-cols-2 lg:grid-cols-4">
          <div
            v-for="row in growthRows"
            :key="row.key"
            class="flex items-center justify-between rounded-lg border border-n-weak px-3 py-2 dark:border-n-slate-6"
          >
            <span class="text-xs text-n-slate-11">{{ row.label }}</span>
            <span
              class="text-sm font-semibold tabular-nums"
              :class="growthClass(row.key, row.value)"
            >
              {{ growthLabel(row.key, row.value) }}
            </span>
          </div>
        </div>
      </section>

      <section>
        <h3 class="mb-3 text-sm font-semibold uppercase tracking-wide text-n-slate-11">
          {{ t('OVERVIEW_REPORTS.OWNER_STATS.PLAYERS') }}
        </h3>
        <div class="grid gap-3 sm:grid-cols-2 lg:grid-cols-5">
          <div class="rounded-lg border border-n-weak p-4 dark:border-n-slate-6">
            <p class="text-xs font-medium text-n-slate-11">
              {{ t('OVERVIEW_REPORTS.OWNER_STATS.TOTAL_PLAYERS') }}
            </p>
            <p class="mt-1 text-2xl font-bold tabular-nums text-n-slate-12">
              {{ stats.players.total }}
            </p>
          </div>
          <div class="rounded-lg border border-n-weak p-4 dark:border-n-slate-6">
            <p class="text-xs font-medium text-n-slate-11">
              {{ t('OVERVIEW_REPORTS.OWNER_STATS.NEW_THIS_WEEK') }}
            </p>
            <p class="mt-1 text-2xl font-bold tabular-nums text-green-700 dark:text-green-400">
              {{ stats.players.new_this_week }}
            </p>
          </div>
          <div
            class="rounded-lg border p-4"
            :class="statCardTone('ai_rate')"
          >
            <p class="text-xs font-medium text-n-slate-11">
              {{ t('OVERVIEW_REPORTS.OWNER_STATS.VIP') }}
            </p>
            <p class="mt-1 text-2xl font-bold tabular-nums text-n-slate-12">
              {{ stats.players.vip }}
            </p>
          </div>
          <div
            class="rounded-lg border p-4"
            :class="statCardTone('escalation')"
          >
            <p class="text-xs font-medium text-n-slate-11">
              {{ t('OVERVIEW_REPORTS.OWNER_STATS.DORMANT') }}
            </p>
            <p class="mt-1 text-2xl font-bold tabular-nums text-red-700 dark:text-red-400">
              {{ stats.players.dormant }}
            </p>
          </div>
          <div
            class="rounded-lg border border-green-200/80 bg-green-50/40 p-4 dark:border-green-900/50 dark:bg-green-950/20"
          >
            <p class="text-xs font-medium text-n-slate-11">
              {{ t('OVERVIEW_REPORTS.OWNER_STATS.ACTIVE_NOW') }}
            </p>
            <p class="mt-1 text-2xl font-bold tabular-nums text-green-700 dark:text-green-400">
              {{ stats.players.active_now }}
            </p>
          </div>
        </div>
      </section>

      <section>
        <h3 class="mb-3 text-sm font-semibold uppercase tracking-wide text-n-slate-11">
          {{ t('OVERVIEW_REPORTS.OWNER_STATS.AI_PERFORMANCE') }}
        </h3>
        <div class="grid gap-3 lg:grid-cols-3">
          <div class="rounded-lg border border-n-weak p-4 dark:border-n-slate-6">
            <p class="text-xs font-medium text-n-slate-11">
              {{ t('OVERVIEW_REPORTS.OWNER_STATS.AVG_MSGS_AI_CONV') }}
            </p>
            <p class="mt-1 text-3xl font-bold tabular-nums text-n-slate-12">
              {{ stats.ai_performance.avg_messages_per_ai_conversation }}
            </p>
          </div>
          <div
            class="rounded-lg border p-4"
            :class="statCardTone('escalation')"
          >
            <p class="text-xs font-medium text-n-slate-11">
              {{ t('OVERVIEW_REPORTS.OWNER_STATS.ESCALATION_RATE') }}
            </p>
            <p class="mt-1 text-3xl font-bold tabular-nums text-red-700 dark:text-red-400">
              {{ formatPercent(stats.ai_performance.escalation_rate_percent) }}
            </p>
          </div>
          <div class="rounded-lg border border-n-weak p-4 dark:border-n-slate-6 lg:col-span-1">
            <p class="mb-2 text-xs font-medium text-n-slate-11">
              {{ t('OVERVIEW_REPORTS.OWNER_STATS.TOP_QUESTIONS') }}
            </p>
            <ul
              v-if="stats.ai_performance.top_questions.length"
              class="space-y-2"
            >
              <li
                v-for="(q, idx) in stats.ai_performance.top_questions"
                :key="idx"
                class="flex justify-between gap-2 text-sm text-n-slate-12"
              >
                <span class="line-clamp-2">{{ q.text }}</span>
                <span class="shrink-0 font-semibold tabular-nums text-n-slate-11">{{ q.count }}</span>
              </li>
            </ul>
            <p
              v-else
              class="text-sm text-n-slate-11"
            >
              {{ t('OVERVIEW_REPORTS.OWNER_STATS.NO_QUESTIONS') }}
            </p>
          </div>
        </div>
      </section>
    </div>
  </div>
</template>
