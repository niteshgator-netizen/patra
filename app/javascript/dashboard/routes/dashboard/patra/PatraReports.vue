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

const maxRevenueNet = computed(() => {
  const rows = stats.value?.revenue_by_game || [];
  return Math.max(...rows.map(r => Math.abs(r.net)), 1);
});

const maxVolumeDay = computed(() => {
  const rows = stats.value?.conversation_volume_by_day || [];
  return Math.max(...rows.map(r => r.count), 1);
});

const maxHeatmapCell = computed(() => {
  const grid = stats.value?.busiest_hours?.grid || [];
  return Math.max(...grid.flat(), 1);
});

const heatmapCellClass = count => {
  if (!count) return 'bg-n-alpha-1';
  const ratio = count / maxHeatmapCell.value;
  if (ratio > 0.75) return 'bg-n-brand';
  if (ratio > 0.5) return 'bg-n-brand/70';
  if (ratio > 0.25) return 'bg-n-brand/40';
  return 'bg-n-brand/20';
};

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
  <div class="pat-page-wrap">
    <div class="pat-page-main">
      <div class="flex flex-col w-full max-w-6xl gap-6 p-6">
        <header>
          <div class="flex items-center justify-between gap-4">
            <div>
              <h1 class="text-2xl font-semibold text-n-slate-12">
                {{ $t('PATRA.REPORTS.TITLE') }}
              </h1>
              <p class="mt-1 text-sm text-n-slate-11">
                {{ $t('PATRA.REPORTS.SUBTITLE') }}
              </p>
            </div>
            <a
              v-if="stats?.export_url"
              :href="stats.export_url"
              class="rounded-lg border border-n-weak px-3 py-2 text-sm text-n-slate-12 hover:bg-n-alpha-2"
            >
              {{ $t('PATRA.REPORTS.EXPORT') }}
            </a>
          </div>
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
                    <th class="pb-2 text-right">
                      {{ $t('PATRA.REPORTS.LOADS') }}
                    </th>
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
              {{ $t('PATRA.REPORTS.REVENUE_BY_GAME') }}
            </h2>
            <div v-if="stats.revenue_by_game?.length" class="space-y-3">
              <div v-for="game in stats.revenue_by_game" :key="game.slug">
                <div class="mb-1 flex justify-between text-xs text-n-slate-11">
                  <span>{{ game.name }}</span>
                  <span
                    :class="game.net >= 0 ? 'text-n-brand' : 'text-n-ruby-11'"
                  >
                    ${{ game.net }}
                  </span>
                </div>
                <div class="h-3 overflow-hidden rounded-full bg-n-alpha-2">
                  <div
                    class="h-full rounded-full"
                    :class="game.net >= 0 ? 'bg-n-brand' : 'bg-n-ruby-9'"
                    :style="{
                      width: `${(Math.abs(game.net) / maxRevenueNet) * 100}%`,
                    }"
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
              {{ $t('PATRA.REPORTS.CONVERSATION_VOLUME') }}
            </h2>
            <div
              v-if="stats.conversation_volume_by_day?.length"
              class="flex items-end gap-1 h-32"
            >
              <div
                v-for="row in stats.conversation_volume_by_day"
                :key="row.date"
                class="flex flex-1 flex-col items-center justify-end gap-1 min-w-0"
              >
                <div
                  class="w-full rounded-t bg-n-brand min-h-[2px]"
                  :style="{ height: `${(row.count / maxVolumeDay) * 100}%` }"
                  :title="`${row.date}: ${row.count}`"
                />
                <span
                  class="text-[9px] text-n-slate-10 truncate w-full text-center"
                >
                  {{ row.date.slice(5) }}
                </span>
              </div>
            </div>
            <p v-else class="text-sm text-n-slate-11">
              {{ $t('PATRA.REPORTS.NO_DATA') }}
            </p>
          </section>

          <section class="rounded-xl border border-n-weak bg-n-solid-1 p-4">
            <h2 class="mb-4 text-sm font-semibold text-n-slate-12">
              {{ $t('PATRA.REPORTS.BUSIEST_HOURS') }}
            </h2>
            <div
              v-if="stats.busiest_hours?.grid?.length"
              class="overflow-x-auto"
            >
              <div
                class="inline-grid gap-0.5"
                style="grid-template-columns: 32px repeat(24, 1fr)"
              >
                <div />
                <span
                  v-for="hour in stats.busiest_hours.hours"
                  :key="hour"
                  class="text-center text-[9px] text-n-slate-10"
                >
                  {{ hour % 6 === 0 ? hour : '' }}
                </span>
                <template
                  v-for="(dayRow, dayIndex) in stats.busiest_hours.grid"
                  :key="stats.busiest_hours.days[dayIndex]"
                >
                  <span class="text-[10px] text-n-slate-10 pr-1 text-right">
                    {{ stats.busiest_hours.days[dayIndex] }}
                  </span>
                  <div
                    v-for="(count, hourIndex) in dayRow"
                    :key="`${dayIndex}-${hourIndex}`"
                    class="size-3 rounded-sm"
                    :class="heatmapCellClass(count)"
                    :title="`${stats.busiest_hours.days[dayIndex]} ${hourIndex}:00 — ${count}`"
                  />
                </template>
              </div>
            </div>
            <p v-else class="text-sm text-n-slate-11">
              {{ $t('PATRA.REPORTS.NO_DATA') }}
            </p>
          </section>

          <section class="rounded-xl border border-n-weak bg-n-solid-1 p-4">
            <h2 class="mb-4 text-sm font-semibold text-n-slate-12">
              {{ $t('PATRA.REPORTS.PAYMENT_VOLUME') }}
            </h2>
            <div v-if="stats.payment_volume?.length" class="space-y-3">
              <div v-for="row in stats.payment_volume" :key="row.date">
                <div class="mb-1 flex justify-between text-xs text-n-slate-11">
                  <span>{{ row.date }}</span>
                  <span> ${{ row.deposits }} / ${{ row.cashouts }} </span>
                </div>
                <div
                  class="flex h-2 gap-1 overflow-hidden rounded-full bg-n-alpha-2"
                >
                  <div
                    class="h-full rounded-full bg-n-brand"
                    :style="{
                      width: `${(row.deposits / maxPaymentDay) * 100}%`,
                    }"
                  />
                  <div
                    class="h-full rounded-full bg-n-ruby-9"
                    :style="{
                      width: `${(row.cashouts / maxPaymentDay) * 100}%`,
                    }"
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
            <table
              v-if="stats.agent_performance?.length"
              class="w-full text-sm"
            >
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
    </div>
  </div>
</template>

<style scoped>
.pat-page-wrap {
  --canvas: #050409;
  --surface: #0c0b12;
  --surface-2: #131119;
  --surface-3: #1b1925;
  --surface-4: #252233;
  --border: #171520;
  --border-hi: #2e2940;
  --patra: #6e56cf;
  --patra-3: #a78bfa;
  --text: #ededf2;
  --text-2: #a8a6b6;
  --text-3: #75727f;
  --text-4: #54515e;
  --green: #3fb950;
  --red: #f85149;

  position: relative;
  min-height: 100%;
  margin-left: -24px;
  margin-right: -24px;
  padding: 0 24px 24px;
  color: var(--text);
  font-family: 'Inter', sans-serif;
  background: var(--canvas);
}

.pat-page-main {
  position: relative;
  z-index: 1;
}

.pat-page-wrap :deep(.text-heading-1),
.pat-page-wrap :deep(h1),
.pat-page-wrap :deep(h2) {
  color: var(--text) !important;
}

.pat-page-wrap :deep(.text-n-slate-12) {
  color: var(--text) !important;
}

.pat-page-wrap :deep(.text-n-slate-11) {
  color: var(--text-2) !important;
}

.pat-page-wrap :deep(.text-n-slate-10),
.pat-page-wrap :deep(.text-n-slate-9) {
  color: var(--text-3) !important;
}

.pat-page-wrap :deep(.text-n-slate-6),
.pat-page-wrap :deep(.text-n-slate-7),
.pat-page-wrap :deep(.text-n-slate-8) {
  color: var(--text-4) !important;
}

.pat-page-wrap :deep(.bg-n-surface-1),
.pat-page-wrap :deep(.bg-n-solid-1) {
  background: var(--canvas) !important;
}

.pat-page-wrap :deep(.bg-n-surface-2),
.pat-page-wrap :deep(.bg-n-solid-2),
.pat-page-wrap :deep(.bg-n-solid-3) {
  background: var(--surface) !important;
}

.pat-page-wrap :deep(.bg-n-alpha-1),
.pat-page-wrap :deep(.bg-n-alpha-2) {
  background: var(--surface-2) !important;
}

.pat-page-wrap :deep(.bg-n-slate-1),
.pat-page-wrap :deep(.bg-n-slate-2) {
  background: var(--surface-2) !important;
}

.pat-page-wrap :deep(.bg-n-slate-3) {
  background: var(--surface-3) !important;
}

.pat-page-wrap :deep(.rounded-xl.border),
.pat-page-wrap :deep(.rounded-lg.border) {
  border-color: var(--border) !important;
}

.pat-page-wrap :deep(.border-n-weak),
.pat-page-wrap :deep(.border-n-container),
.pat-page-wrap :deep(.outline-n-weak),
.pat-page-wrap :deep(.outline-n-container),
.pat-page-wrap :deep(.dark\:border-n-slate-6) {
  border-color: var(--border) !important;
  outline-color: var(--border) !important;
}

.pat-page-wrap :deep(.divide-y > *) {
  border-color: var(--border) !important;
}

.pat-page-wrap :deep(.group-hover\:bg-n-alpha-2) {
  background: var(--surface-2) !important;
  border-color: var(--border-hi) !important;
  color: var(--text-2) !important;
}

.pat-page-wrap :deep(.group:hover .group-hover\:bg-n-alpha-2) {
  background: var(--surface-3) !important;
  border-color: var(--patra) !important;
  color: var(--text) !important;
}

.pat-page-wrap :deep(thead) {
  background: var(--surface-2) !important;
}

.pat-page-wrap :deep(thead th) {
  color: var(--text-4) !important;
  border-bottom: 1px solid var(--border);
}

.pat-page-wrap :deep(tbody tr:hover) {
  background: var(--surface-2) !important;
}

.pat-page-wrap :deep(tbody td) {
  color: var(--text);
  border-color: var(--border);
}

.pat-page-wrap :deep(input),
.pat-page-wrap :deep(textarea),
.pat-page-wrap :deep(select) {
  background: var(--surface-2);
  border: 1px solid var(--border);
  color: var(--text);
  border-radius: 8px;
}

.pat-page-wrap :deep(input:focus),
.pat-page-wrap :deep(textarea:focus),
.pat-page-wrap :deep(select:focus) {
  border-color: var(--patra);
  outline: none;
  box-shadow: 0 0 0 3px rgba(110, 86, 207, 0.11);
}

.pat-page-wrap :deep(.text-n-teal-10),
.pat-page-wrap :deep(.text-n-teal-11) {
  color: var(--green) !important;
}

.pat-page-wrap :deep(.text-n-ruby-9),
.pat-page-wrap :deep(.text-n-ruby-10) {
  color: var(--red) !important;
}

.pat-page-wrap :deep(.fixed.z-50.bg-n-slate-12) {
  background: var(--surface-4) !important;
  border: 1px solid var(--border-hi);
  color: var(--text) !important;
}

.pat-page-wrap :deep(.animate-loader-pulse) {
  background: var(--surface-3) !important;
}
</style>
