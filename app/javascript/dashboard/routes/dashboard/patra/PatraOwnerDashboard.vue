<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import PatraDashboardAPI from 'dashboard/api/patraDashboard';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import GameHealthDashboard from 'dashboard/components/widgets/GameHealthDashboard.vue';
import OnboardingChecklist from 'dashboard/components/widgets/OnboardingChecklist.vue';

const { t } = useI18n();

const loading = ref(true);
const stats = ref(null);
const error = ref(null);

const channelEntries = computed(() => {
  const volume = stats.value?.volume_by_channel || {};
  const max = Math.max(...Object.values(volume), 1);
  return Object.entries(volume).map(([name, count]) => ({
    name,
    count,
    pct: Math.round((count / max) * 100),
  }));
});

onMounted(async () => {
  try {
    const { data } = await PatraDashboardAPI.get();
    stats.value = data;
  } catch (e) {
    error.value = e.message || 'Failed to load dashboard';
  } finally {
    loading.value = false;
  }
});
</script>

<template>
  <div class="flex flex-col w-full max-w-5xl gap-6 p-6">
    <header>
      <h1 class="text-2xl font-semibold text-n-slate-12">
        {{ $t('PATRA.DASHBOARD.TITLE') }}
      </h1>
      <p class="mt-1 text-sm text-n-slate-11">
        {{ $t('PATRA.DASHBOARD.SUBTITLE') }}
      </p>
    </header>

    <div v-if="loading" class="flex justify-center py-16">
      <Spinner />
    </div>

    <p v-else-if="error" class="text-n-ruby-11">{{ error }}</p>

    <template v-else-if="stats">
      <OnboardingChecklist class="mb-4" />
      <div class="grid grid-cols-2 gap-4 md:grid-cols-4">
        <div class="rounded-xl border border-n-weak bg-n-solid-1 p-4">
          <p class="text-xs font-medium uppercase text-n-slate-11">
            {{ $t('PATRA.DASHBOARD.CONVERSATIONS_TODAY') }}
          </p>
          <p class="mt-1 text-2xl font-bold text-n-slate-12">
            {{ stats.conversations_today }}
          </p>
        </div>
        <div class="rounded-xl border border-n-weak bg-n-solid-1 p-4">
          <p class="text-xs font-medium uppercase text-n-slate-11">
            {{ $t('PATRA.DASHBOARD.MESSAGES_IN') }}
          </p>
          <p class="mt-1 text-2xl font-bold text-n-slate-12">
            {{ stats.messages_in_today }}
          </p>
        </div>
        <div class="rounded-xl border border-n-weak bg-n-solid-1 p-4">
          <p class="text-xs font-medium uppercase text-n-slate-11">
            {{ $t('PATRA.DASHBOARD.MESSAGES_OUT') }}
          </p>
          <p class="mt-1 text-2xl font-bold text-n-slate-12">
            {{ stats.messages_out_today }}
          </p>
        </div>
        <div class="rounded-xl border border-n-weak bg-n-solid-1 p-4">
          <p class="text-xs font-medium uppercase text-n-slate-11">
            {{ $t('PATRA.DASHBOARD.AI_HANDLE_RATE') }}
          </p>
          <p class="mt-1 text-2xl font-bold text-n-slate-12">
            {{ stats.ai_handle_rate }}%
          </p>
        </div>
        <div class="rounded-xl border border-n-weak bg-n-solid-1 p-4">
          <p class="mt-1 text-2xl font-bold text-n-slate-12">
            {{ stats.new_customers_today }}
          </p>
        </div>
        <div class="rounded-xl border border-n-weak bg-n-solid-1 p-4">
          <p class="text-xs font-medium uppercase text-n-slate-11">
            {{ $t('PATRA.DASHBOARD.FLAGGED_REVIEW') }}
          </p>
          <p class="mt-1 text-2xl font-bold text-n-slate-12">
            {{ stats.flagged_for_review }}
          </p>
        </div>
        <div class="rounded-xl border border-n-weak bg-n-solid-1 p-4">
          <p class="text-xs font-medium uppercase text-n-slate-11">
            {{ $t('PATRA.DASHBOARD.NET_TODAY') }}
          </p>
          <p class="mt-1 text-2xl font-bold text-n-slate-12">
            ${{ stats.net_today }}
          </p>
        </div>
      </div>

      <div class="grid gap-6 md:grid-cols-2">
        <div class="rounded-xl border border-n-weak bg-n-solid-1 p-4">
          <h2 class="mb-4 text-sm font-semibold text-n-slate-12">
            {{ $t('PATRA.DASHBOARD.VOLUME_BY_CHANNEL') }}
          </h2>
          <div v-if="channelEntries.length" class="space-y-3">
            <div v-for="row in channelEntries" :key="row.name">
              <div class="mb-1 flex justify-between text-xs">
                <span class="truncate text-n-slate-12">{{ row.name }}</span>
                <span class="text-n-slate-11">{{ row.count }}</span>
              </div>
              <div class="h-2 overflow-hidden rounded-full bg-n-alpha-2">
                <div
                  class="h-full rounded-full bg-n-brand"
                  :style="{ width: `${row.pct}%` }"
                />
              </div>
            </div>
          </div>
          <p v-else class="text-sm text-n-slate-11">
            {{ $t('PATRA.DASHBOARD.NO_DATA') }}
          </p>
        </div>

        <div class="rounded-xl border border-n-weak bg-n-solid-1 p-4">
          <h2 class="mb-4 text-sm font-semibold text-n-slate-12">
            {{ $t('PATRA.DASHBOARD.ACTIVE_AGENTS') }}
          </h2>
          <ul v-if="stats.active_agents?.length" class="space-y-2">
            <li
              v-for="agent in stats.active_agents"
              :key="agent.name"
              class="flex items-center justify-between text-sm"
            >
              <span class="text-n-slate-12">{{ agent.name }}</span>
              <span class="rounded-full bg-green-100 px-2 py-0.5 text-xs text-green-800 dark:bg-green-900/30 dark:text-green-300">
                {{ agent.role }}
              </span>
            </li>
          </ul>
          <p v-else class="text-sm text-n-slate-11">
            {{ $t('PATRA.DASHBOARD.NO_AGENTS') }}
          </p>
        </div>
      </div>

      <GameHealthDashboard />

      <div class="rounded-xl border border-dashed border-n-weak bg-n-alpha-1 p-6 text-center">
        <p class="text-sm font-medium text-n-slate-12">
          {{ $t('PATRA.DASHBOARD.LOADS_CASHOUTS') }}
        </p>
        <p class="mt-1 text-xs text-n-slate-11">
          {{ $t('PATRA.DASHBOARD.LOADS_CASHOUTS_DETAIL', {
            loads: stats.loads_today?.amount || 0,
            loadCount: stats.loads_today?.count || 0,
            cashouts: stats.cashouts_today?.amount || 0,
            cashoutCount: stats.cashouts_today?.count || 0,
          }) }}
        </p>
      </div>
    </template>
  </div>
</template>
