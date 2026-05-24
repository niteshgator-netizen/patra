<script setup>
import { computed, onMounted, ref } from 'vue';
import PatraReportsAPI from 'dashboard/api/patraReports';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const loading = ref(true);
const stats = ref(null);
const error = ref(null);

const formatTrend = value => {
  if (value == null || value === 0) return '—';
  const sign = value > 0 ? '+' : '';
  return `${sign}${value}%`;
};

const maxPaymentDay = computed(() => {
  const rows = stats.value?.payment_volume || [];
  return Math.max(...rows.flatMap(r => [r.deposits, r.cashouts]), 1);
});

onMounted(async () => {
  try {
    const { data } = await PatraReportsAPI.get();
    stats.value = data;
  } catch (e) {
    error.value = e.message || 'Failed to load reports';
  } finally {
    loading.value = false;
  }
});
</script>

<template>
  <div class="flex flex-col w-full max-w-6xl gap-6 p-6">
    <header>
      <h1 class="text-2xl font-semibold text-n-slate-12">
        {{ $t('PATRA.REPORTS.TITLE') }}
      </h1>
      <p class="mt-1 text-sm text-n-slate-11">
        {{ $t('PATRA.REPORTS.SUBTITLE') }}
      </p>
    </header>

    <div v-if="loading" class="flex justify-center py-16">
      <Spinner />
    </div>

    <p v-else-if="error" class="text-n-ruby-11">{{ error }}</p>

    <template v-else-if="stats">
      <section>
        <h2 class="mb-3 text-sm font-semibold text-n-slate-12">
          {{ $t('PATRA.REPORTS.TODAY') }}
        </h2>
        <div class="grid grid-cols-2 gap-4 md:grid-cols-3">
          <div class="rounded-xl border border-n-weak bg-n-solid-1 p-4">
            <p class="text-xs font-medium uppercase text-n-slate-11">
              {{ $t('PATRA.REPORTS.CONVERSATIONS_OPENED') }}
            </p>
            <p class="mt-1 text-2xl font-bold text-n-slate-12">
              {{ stats.today.conversations_opened }}
            </p>
          </div>
          <div class="rounded-xl border border-n-weak bg-n-solid-1 p-4">
            <p class="text-xs font-medium uppercase text-n-slate-11">
              {{ $t('PATRA.REPORTS.RESOLVED') }}
            </p>
            <p class="mt-1 text-2xl font-bold text-n-slate-12">
              {{ stats.today.resolved }}
            </p>
          </div>
          <div class="rounded-xl border border-n-weak bg-n-solid-1 p-4">
            <p class="text-xs font-medium uppercase text-n-slate-11">
              {{ $t('PATRA.REPORTS.AI_HANDLE_RATE') }}
            </p>
            <p class="mt-1 text-2xl font-bold text-n-slate-12">
              {{ stats.today.ai_handle_rate }}%
            </p>
          </div>
        </div>
      </section>

      <section>
        <h2 class="mb-3 text-sm font-semibold text-n-slate-12">
          {{ $t('PATRA.REPORTS.THIS_WEEK') }}
        </h2>
        <div class="grid grid-cols-2 gap-4 md:grid-cols-4">
          <div class="rounded-xl border border-n-weak bg-n-solid-1 p-4">
            <p class="text-xs font-medium uppercase text-n-slate-11">
              {{ $t('PATRA.REPORTS.CONVERSATIONS_OPENED') }}
            </p>
            <p class="mt-1 text-xl font-bold text-n-slate-12">
              {{ stats.this_week.conversations_opened }}
            </p>
            <p class="mt-1 text-xs text-n-slate-11">
              {{ formatTrend(stats.week_trend.conversations.change) }}
            </p>
          </div>
          <div class="rounded-xl border border-n-weak bg-n-solid-1 p-4">
            <p class="text-xs font-medium uppercase text-n-slate-11">
              {{ $t('PATRA.REPORTS.RESOLVED') }}
            </p>
            <p class="mt-1 text-xl font-bold text-n-slate-12">
              {{ stats.this_week.resolved }}
            </p>
            <p class="mt-1 text-xs text-n-slate-11">
              {{ formatTrend(stats.week_trend.resolved.change) }}
            </p>
          </div>
          <div class="rounded-xl border border-n-weak bg-n-solid-1 p-4">
            <p class="text-xs font-medium uppercase text-n-slate-11">
              {{ $t('PATRA.REPORTS.AI_HANDLE_RATE') }}
            </p>
            <p class="mt-1 text-xl font-bold text-n-slate-12">
              {{ stats.this_week.ai_handle_rate }}%
            </p>
            <p class="mt-1 text-xs text-n-slate-11">
              {{ formatTrend(stats.week_trend.ai_handle_rate.change) }}
            </p>
          </div>
        </div>
      </section>

      <div class="grid gap-6 md:grid-cols-2">
        <section class="rounded-xl border border-n-weak bg-n-solid-1 p-4">
          <h2 class="mb-4 text-sm font-semibold text-n-slate-12">
            {{ $t('PATRA.REPORTS.TOP_PLAYERS') }}
          </h2>
          <table v-if="stats.top_players?.length" class="w-full text-sm">
            <thead>
              <tr class="text-left text-n-slate-11">
                <th class="pb-2">{{ $t('PATRA.REPORTS.PLAYER') }}</th>
                <th class="pb-2 text-right">
                  {{ $t('PATRA.REPORTS.CONVERSATIONS') }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="player in stats.top_players"
                :key="player.contact_id"
                class="border-t border-n-weak"
              >
                <td class="py-2 text-n-slate-12">{{ player.name }}</td>
                <td class="py-2 text-right text-n-slate-11">
                  {{ player.conversations }}
                </td>
              </tr>
            </tbody>
          </table>
          <p v-else class="text-sm text-n-slate-11">
            {{ $t('PATRA.REPORTS.NO_DATA') }}
          </p>
        </section>

        <section class="rounded-xl border border-n-weak bg-n-solid-1 p-4">
          <h2 class="mb-4 text-sm font-semibold text-n-slate-12">
            {{ $t('PATRA.REPORTS.GAME_USAGE') }}
          </h2>
          <table v-if="stats.game_usage?.length" class="w-full text-sm">
            <thead>
              <tr class="text-left text-n-slate-11">
                <th class="pb-2">{{ $t('PATRA.REPORTS.GAME') }}</th>
                <th class="pb-2 text-right">{{ $t('PATRA.REPORTS.LOADS') }}</th>
                <th class="pb-2 text-right">
                  {{ $t('PATRA.REPORTS.CASHOUTS') }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="game in stats.game_usage"
                :key="game.slug"
                class="border-t border-n-weak"
              >
                <td class="py-2 text-n-slate-12">{{ game.name }}</td>
                <td class="py-2 text-right text-n-slate-11">
                  {{ game.loads }}
                </td>
                <td class="py-2 text-right text-n-slate-11">
                  {{ game.cashouts }}
                </td>
              </tr>
            </tbody>
          </table>
          <p v-else class="text-sm text-n-slate-11">
            {{ $t('PATRA.REPORTS.NO_DATA') }}
          </p>
        </section>
      </div>

      <section class="rounded-xl border border-n-weak bg-n-solid-1 p-4">
        <h2 class="mb-4 text-sm font-semibold text-n-slate-12">
          {{ $t('PATRA.REPORTS.PAYMENT_VOLUME') }}
        </h2>
        <div v-if="stats.payment_volume?.length" class="space-y-3">
          <div v-for="row in stats.payment_volume" :key="row.date">
            <div class="mb-1 flex justify-between text-xs text-n-slate-11">
              <span>{{ row.date }}</span>
              <span>
                ${{ row.deposits }} / ${{ row.cashouts }}
              </span>
            </div>
            <div class="flex h-2 gap-1 overflow-hidden rounded-full bg-n-alpha-2">
              <div
                class="h-full rounded-full bg-n-brand"
                :style="{ width: `${(row.deposits / maxPaymentDay) * 100}%` }"
              />
              <div
                class="h-full rounded-full bg-n-ruby-9"
                :style="{ width: `${(row.cashouts / maxPaymentDay) * 100}%` }"
              />
            </div>
          </div>
        </div>
        <p v-else class="text-sm text-n-slate-11">
          {{ $t('PATRA.REPORTS.NO_DATA') }}
        </p>
      </section>

      <section class="rounded-xl border border-n-weak bg-n-solid-1 p-4">
        <h2 class="mb-4 text-sm font-semibold text-n-slate-12">
          {{ $t('PATRA.REPORTS.AGENT_PERFORMANCE') }}
        </h2>
        <table v-if="stats.agent_performance?.length" class="w-full text-sm">
          <thead>
            <tr class="text-left text-n-slate-11">
              <th class="pb-2">{{ $t('PATRA.REPORTS.AGENT') }}</th>
              <th class="pb-2 text-right">
                {{ $t('PATRA.REPORTS.MESSAGES_TODAY') }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="agent in stats.agent_performance"
              :key="agent.user_id"
              class="border-t border-n-weak"
            >
              <td class="py-2 text-n-slate-12">{{ agent.name }}</td>
              <td class="py-2 text-right text-n-slate-11">
                {{ agent.messages }}
              </td>
            </tr>
          </tbody>
        </table>
        <p v-else class="text-sm text-n-slate-11">
          {{ $t('PATRA.REPORTS.NO_DATA') }}
        </p>
      </section>
    </template>
  </div>
</template>
