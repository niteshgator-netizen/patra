<script setup>
import { computed, onMounted, onUnmounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import PatraDashboardAPI from 'dashboard/api/patraDashboard';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import GameHealthDashboard from 'dashboard/components/widgets/GameHealthDashboard.vue';
import OnboardingChecklist from 'dashboard/components/widgets/OnboardingChecklist.vue';

const { t } = useI18n();

const loading = ref(true);
const stats = ref(null);
const error = ref(null);
const rootRef = ref(null);
const spotlightRef = ref(null);
const emptyPlaceholder = '—';
const activeRange = ref('today');
const heatmapDays = ['Sat', 'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri'];
const heatmapHours = Array.from({ length: 24 }, (_, i) => i);
const channelColors = ['#0866FF', '#8B5CF6', '#58A6FF', '#3FB950', '#E3A008'];
const rangeSevenDays = '7 days';
const rangeThirtyDays = '30 days';
const periodWeekToggle = 'this week ▾';
const donutHandledLabel = 'AI handled';
const legendAiHandled = 'Patra AI handled';
const legendEscalated = 'Escalated to human';
const legendStillOpen = 'Still open';
const heatmapPeriodSuffix = '· last 7 days';
const heatmapLess = 'Less';
const heatmapMore = 'More';
const agentOnlineLabel = 'online';

const channelEntries = computed(() => {
  const volume = stats.value?.volume_by_channel || {};
  const max = Math.max(...Object.values(volume), 1);
  return Object.entries(volume).map(([name, count], index) => ({
    name,
    count,
    pct: Math.round((count / max) * 100),
    color: channelColors[index % channelColors.length],
  }));
});

const formattedNetToday = computed(() => `$${stats.value?.net_today ?? 0}`);

const gamePerformanceCounts = computed(() => {
  const perf = stats.value?.game_performance;
  if (!perf) return '';
  return `${perf.active}/${perf.total}`;
});

const gamesOkEmoji = computed(() => {
  const perf = stats.value?.game_performance;
  if (!perf) return '';
  return perf.active === perf.total ? '🟢' : '⚠️';
});

const activeAgentsCount = computed(
  () => stats.value?.active_agents?.length ?? 0
);

const todayLabel = computed(() =>
  new Intl.DateTimeFormat(undefined, {
    weekday: 'long',
    month: 'long',
    day: 'numeric',
  }).format(new Date())
);

const headerSubline = computed(
  () => `${t('PATRA.DASHBOARD.SUBTITLE')} · ${todayLabel.value}`
);

const loadsFooterLine = computed(() => {
  const amount = stats.value?.loads_today?.amount ?? 0;
  const count = stats.value?.loads_today?.count ?? 0;
  return `$${amount} · ${count} txns`;
});

const cashoutsFooterLine = computed(() => {
  const amount = stats.value?.cashouts_today?.amount ?? 0;
  const count = stats.value?.cashouts_today?.count ?? 0;
  return `$${amount} · ${count} txns`;
});

const donutOffset = computed(() => {
  const rate = Number(stats.value?.ai_handle_rate) || 0;
  const circumference = 377;
  return circumference - (circumference * rate) / 100;
});

function formatPercent(value) {
  return `${value ?? 0}%`;
}

function channelColor(index) {
  return channelColors[index % channelColors.length];
}

function noopPlaceholder() {}

function setRange(range) {
  if (range === 'today') activeRange.value = 'today';
  else noopPlaceholder();
}

async function loadStats(showSpinner = false) {
  if (showSpinner) loading.value = true;
  error.value = null;
  try {
    const { data } = await PatraDashboardAPI.get();
    stats.value = data;
  } catch (e) {
    error.value = e.message || 'Failed to load dashboard';
  } finally {
    if (showSpinner) loading.value = false;
  }
}

function onMouseMove(event) {
  const spot = spotlightRef.value;
  if (spot) {
    spot.style.left = `${event.clientX}px`;
    spot.style.top = `${event.clientY}px`;
    spot.style.opacity = '1';
  }

  const card = event.target.closest?.('.patra-card, .patra-kpi');
  if (card) {
    const rect = card.getBoundingClientRect();
    card.style.setProperty('--gx', `${event.clientX - rect.left}px`);
    card.style.setProperty('--gy', `${event.clientY - rect.top}px`);
  }

  const kpi = event.target.closest?.('.patra-kpi');
  if (kpi) {
    const rect = kpi.getBoundingClientRect();
    kpi.style.setProperty('--mx', `${event.clientX - rect.left}px`);
    kpi.style.setProperty('--my', `${event.clientY - rect.top}px`);
  }
}

function onMouseLeave() {
  if (spotlightRef.value) spotlightRef.value.style.opacity = '0';
}

onMounted(async () => {
  await loadStats(true);
  rootRef.value?.addEventListener('mousemove', onMouseMove);
  document.addEventListener('mouseleave', onMouseLeave);
});

onUnmounted(() => {
  rootRef.value?.removeEventListener('mousemove', onMouseMove);
  document.removeEventListener('mouseleave', onMouseLeave);
});
</script>

<template>
  <div ref="rootRef" class="patra-owner-dashboard">
    <div ref="spotlightRef" class="patra-spotlight" aria-hidden="true" />
    <div class="patra-mesh" aria-hidden="true" />

    <div class="patra-main">
      <div class="patra-topbar">
        <div>
          <h1 class="patra-topbar-title">
            {{ $t('PATRA.DASHBOARD.TITLE') }}
          </h1>
          <div class="patra-topbar-sub">
            {{ headerSubline }}
          </div>
        </div>
        <div class="patra-tb-right">
          <div class="patra-range">
            <button
              type="button"
              class="patra-range-btn"
              :class="{ active: activeRange === 'today' }"
              @click="setRange('today')"
            >
              {{ $t('PATRA.REPORTS.TODAY') }}
            </button>
            <!-- TODO: wire backend -->
            <button
              type="button"
              class="patra-range-btn"
              @click="setRange('7d')"
            >
              {{ rangeSevenDays }}
            </button>
            <!-- TODO: wire backend -->
            <button
              type="button"
              class="patra-range-btn"
              @click="setRange('30d')"
            >
              {{ rangeThirtyDays }}
            </button>
          </div>
          <button type="button" class="patra-btn" @click="loadStats(false)">
            <svg
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="2"
            >
              <path d="M23 4v6h-6M1 20v-6h6" />
              <path
                d="M3.5 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.5 15"
              />
            </svg>
            {{ $t('OVERVIEW_REPORTS.OWNER_STATS.REFRESH') }}
          </button>
        </div>
      </div>

      <div class="patra-content">
        <div v-if="loading" class="patra-loading">
          <Spinner />
        </div>

        <p v-else-if="error" class="patra-error">
          {{ error }}
        </p>

        <template v-else-if="stats">
          <div class="patra-checklist-wrap">
            <OnboardingChecklist />
          </div>

          <div class="patra-kpis">
            <!-- TODO: wire backend — KPI drill-down -->
            <div class="patra-kpi patra-card" @click="noopPlaceholder">
              <div class="patra-kpi-top">
                <div class="patra-kpi-ic patra-kpi-ic-violet">
                  <svg
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="#8B5CF6"
                    stroke-width="2"
                  >
                    <path
                      d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"
                    />
                  </svg>
                </div>
              </div>
              <div class="patra-kpi-n">{{ stats.conversations_today }}</div>
              <div class="patra-kpi-l">
                {{ $t('PATRA.DASHBOARD.CONVERSATIONS_TODAY') }}
              </div>
              <svg
                class="patra-spark"
                viewBox="0 0 100 30"
                preserveAspectRatio="none"
              >
                <polyline
                  points="0,30 100,30"
                  fill="none"
                  stroke="var(--patra-2)"
                  stroke-width="2"
                />
              </svg>
            </div>

            <div class="patra-kpi patra-card" @click="noopPlaceholder">
              <div class="patra-kpi-top">
                <div class="patra-kpi-ic patra-kpi-ic-blue">
                  <svg
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="#58A6FF"
                    stroke-width="2"
                  >
                    <path d="M4 4h16v12H5.2L4 17.2z" />
                  </svg>
                </div>
              </div>
              <div class="patra-kpi-n">{{ stats.messages_in_today }}</div>
              <div class="patra-kpi-l">
                {{ $t('PATRA.DASHBOARD.MESSAGES_IN') }}
              </div>
              <svg
                class="patra-spark"
                viewBox="0 0 100 30"
                preserveAspectRatio="none"
              >
                <polyline
                  points="0,30 100,30"
                  fill="none"
                  stroke="var(--patra-2)"
                  stroke-width="2"
                />
              </svg>
            </div>

            <div class="patra-kpi patra-card" @click="noopPlaceholder">
              <div class="patra-kpi-top">
                <div class="patra-kpi-ic patra-kpi-ic-green">
                  <svg
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="#3FB950"
                    stroke-width="2"
                  >
                    <path d="M22 2L11 13M22 2l-7 20-4-9-9-4z" />
                  </svg>
                </div>
              </div>
              <div class="patra-kpi-n">{{ stats.messages_out_today }}</div>
              <div class="patra-kpi-l">
                {{ $t('PATRA.DASHBOARD.MESSAGES_OUT') }}
              </div>
              <svg
                class="patra-spark"
                viewBox="0 0 100 30"
                preserveAspectRatio="none"
              >
                <polyline
                  points="0,30 100,30"
                  fill="none"
                  stroke="var(--patra-2)"
                  stroke-width="2"
                />
              </svg>
            </div>

            <div class="patra-kpi patra-card" @click="noopPlaceholder">
              <div class="patra-kpi-top">
                <div class="patra-kpi-ic patra-kpi-ic-violet">
                  <svg viewBox="0 0 24 24" fill="#8B5CF6">
                    <path
                      d="M12 2l2.4 7.4H22l-6 4.6 2.3 7.4L12 17l-6.3 4.4L8 14 2 9.4h7.6z"
                    />
                  </svg>
                </div>
              </div>
              <div class="patra-kpi-n patra-kpi-n-accent">
                {{ formatPercent(stats.ai_handle_rate) }}
              </div>
              <div class="patra-kpi-l">
                {{ $t('PATRA.DASHBOARD.AI_HANDLE_RATE') }}
              </div>
              <svg
                class="patra-spark"
                viewBox="0 0 100 30"
                preserveAspectRatio="none"
              >
                <polyline
                  points="0,30 100,30"
                  fill="none"
                  stroke="var(--patra-2)"
                  stroke-width="2"
                />
              </svg>
            </div>

            <div class="patra-kpi patra-card" @click="noopPlaceholder">
              <div class="patra-kpi-top">
                <div class="patra-kpi-ic patra-kpi-ic-red">
                  <svg
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="#F85149"
                    stroke-width="2"
                  >
                    <path
                      d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"
                    />
                    <path d="M12 9v4M12 17h.01" />
                  </svg>
                </div>
              </div>
              <div class="patra-kpi-n patra-kpi-n-warn">
                {{ stats.flagged_for_review }}
              </div>
              <div class="patra-kpi-l">
                {{ $t('PATRA.DASHBOARD.FLAGGED_REVIEW') }}
              </div>
              <svg
                class="patra-spark"
                viewBox="0 0 100 30"
                preserveAspectRatio="none"
              >
                <polyline
                  points="0,30 100,30"
                  fill="none"
                  stroke="var(--patra-2)"
                  stroke-width="2"
                />
              </svg>
            </div>

            <div class="patra-kpi patra-card" @click="noopPlaceholder">
              <div class="patra-kpi-top">
                <div class="patra-kpi-ic patra-kpi-ic-green">
                  <svg
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="#3FB950"
                    stroke-width="2"
                  >
                    <path
                      d="M12 1v22M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6"
                    />
                  </svg>
                </div>
              </div>
              <div class="patra-kpi-n patra-kpi-n-green">
                {{ formattedNetToday }}
              </div>
              <div class="patra-kpi-l">
                {{ $t('PATRA.DASHBOARD.NET_TODAY') }}
              </div>
              <svg
                class="patra-spark"
                viewBox="0 0 100 30"
                preserveAspectRatio="none"
              >
                <polyline
                  points="0,30 100,30"
                  fill="none"
                  stroke="var(--patra-2)"
                  stroke-width="2"
                />
              </svg>
            </div>
          </div>

          <div class="patra-grid">
            <div class="patra-card">
              <div class="patra-card-h">
                <div class="patra-card-t">
                  <span class="patra-card-dot" />
                  {{ $t('PATRA.DASHBOARD.VOLUME_BY_CHANNEL') }}
                </div>
                <span class="patra-card-more">{{
                  $t('PATRA.REPORTS.TODAY')
                }}</span>
              </div>
              <div v-if="channelEntries.length">
                <div
                  v-for="row in channelEntries"
                  :key="row.name"
                  class="patra-ch-row"
                >
                  <div class="patra-ch-ic" :style="{ background: row.color }">
                    <svg
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="#fff"
                      stroke-width="2"
                    >
                      <path d="M10 13a5 5 0 0 0 7 0l3-3a5 5 0 0 0-7-7l-1 1" />
                      <path d="M14 11a5 5 0 0 0-7 0l-3 3a5 5 0 0 0 7 7l1-1" />
                    </svg>
                  </div>
                  <div class="patra-ch-info">
                    <div class="patra-ch-nm">{{ row.name }}</div>
                    <div class="patra-ch-bar">
                      <i
                        :style="{ width: `${row.pct}%`, background: row.color }"
                      />
                    </div>
                  </div>
                  <div class="patra-ch-val">{{ row.count }}</div>
                </div>
              </div>
              <p v-else class="patra-empty">
                {{ $t('PATRA.DASHBOARD.NO_DATA') }}
              </p>
            </div>

            <div class="patra-card">
              <div class="patra-card-h">
                <div class="patra-card-t">
                  <span class="patra-card-dot" />
                  {{ $t('PATRA.DASHBOARD.AI_HANDLE_RATE') }}
                </div>
                <!-- TODO: wire backend -->
                <button
                  type="button"
                  class="patra-card-more patra-card-more-btn"
                  @click="noopPlaceholder"
                >
                  {{ periodWeekToggle }}
                </button>
              </div>
              <div class="patra-donut-wrap">
                <div class="patra-donut">
                  <svg width="150" height="150" viewBox="0 0 150 150">
                    <circle
                      cx="75"
                      cy="75"
                      r="60"
                      fill="none"
                      stroke="var(--surface-3)"
                      stroke-width="16"
                    />
                    <circle
                      cx="75"
                      cy="75"
                      r="60"
                      fill="none"
                      stroke="url(#patraDonutGrad)"
                      stroke-width="16"
                      stroke-linecap="round"
                      :stroke-dasharray="377"
                      :stroke-dashoffset="donutOffset"
                      class="patra-donut-arc"
                    />
                    <defs>
                      <linearGradient
                        id="patraDonutGrad"
                        x1="0"
                        y1="0"
                        x2="1"
                        y2="1"
                      >
                        <stop offset="0" stop-color="#8B5CF6" />
                        <stop offset="1" stop-color="#6E56CF" />
                      </linearGradient>
                    </defs>
                  </svg>
                  <div class="patra-donut-center">
                    <div class="patra-donut-pct">
                      {{ formatPercent(stats.ai_handle_rate) }}
                    </div>
                    <div class="patra-donut-lbl">{{ donutHandledLabel }}</div>
                  </div>
                </div>
                <div class="patra-legend">
                  <div class="patra-leg">
                    <span class="patra-leg-sw patra-leg-sw-ai" />
                    {{ legendAiHandled }}
                    <span class="patra-leg-v">{{
                      formatPercent(stats.ai_handle_rate)
                    }}</span>
                  </div>
                  <!-- TODO: wire backend -->
                  <div class="patra-leg">
                    <span class="patra-leg-sw patra-leg-sw-amber" />
                    {{ legendEscalated }}
                    <span class="patra-leg-v">{{ emptyPlaceholder }}</span>
                  </div>
                  <!-- TODO: wire backend -->
                  <div class="patra-leg">
                    <span class="patra-leg-sw patra-leg-sw-muted" />
                    {{ legendStillOpen }}
                    <span class="patra-leg-v">{{ emptyPlaceholder }}</span>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <div class="patra-grid">
            <div class="patra-card">
              <div class="patra-card-h">
                <div class="patra-card-t">
                  <span class="patra-card-dot" />
                  {{ $t('OVERVIEW_REPORTS.OWNER_STATS.PLAYERS') }}
                </div>
                <!-- TODO: wire backend -->
                <button
                  type="button"
                  class="patra-card-more patra-card-more-btn"
                  @click="noopPlaceholder"
                >
                  {{ $t('OVERVIEW_REPORTS.OWNER_STATS.TOTAL_PLAYERS') }}
                </button>
              </div>
              <div class="patra-mini-stats">
                <div class="patra-ms">
                  <div class="patra-ms-n patra-ms-empty">
                    {{ emptyPlaceholder }}
                  </div>
                  <div class="patra-ms-l">
                    {{ $t('OVERVIEW_REPORTS.OWNER_STATS.TOTAL_PLAYERS') }}
                  </div>
                </div>
                <div class="patra-ms">
                  <div class="patra-ms-n">{{ stats.new_customers_today }}</div>
                  <div class="patra-ms-l">
                    {{ $t('PATRA.DASHBOARD.NEW_CUSTOMERS') }}
                  </div>
                </div>
                <div class="patra-ms">
                  <div class="patra-ms-n patra-ms-empty">
                    {{ emptyPlaceholder }}
                  </div>
                  <div class="patra-ms-l">
                    {{ $t('OVERVIEW_REPORTS.OWNER_STATS.VIP') }}
                  </div>
                </div>
                <div class="patra-ms">
                  <div class="patra-ms-n patra-ms-empty">
                    {{ emptyPlaceholder }}
                  </div>
                  <div class="patra-ms-l">
                    {{ $t('OVERVIEW_REPORTS.OWNER_STATS.DORMANT') }}
                  </div>
                </div>
                <div class="patra-ms">
                  <div class="patra-ms-n patra-ms-empty">
                    {{ emptyPlaceholder }}
                  </div>
                  <div class="patra-ms-l">
                    {{ $t('OVERVIEW_REPORTS.OWNER_STATS.ACTIVE_NOW') }}
                  </div>
                </div>
              </div>
            </div>

            <div class="patra-card">
              <div class="patra-card-h">
                <div class="patra-card-t">
                  <span class="patra-card-dot" />
                  {{ $t('OVERVIEW_REPORTS.OWNER_STATS.AI_PERFORMANCE') }}
                </div>
                <!-- TODO: wire backend -->
                <button
                  type="button"
                  class="patra-card-more patra-card-more-btn"
                  @click="noopPlaceholder"
                >
                  {{ $t('PATRA.REPORTS.THIS_WEEK') }}
                </button>
              </div>
              <div class="patra-ai-perf">
                <div class="patra-ap-row">
                  <span class="patra-ap-k">{{
                    $t('OVERVIEW_REPORTS.OWNER_STATS.AVG_MSGS_AI_CONV')
                  }}</span>
                  <span class="patra-ap-v patra-ap-empty">{{
                    emptyPlaceholder
                  }}</span>
                </div>
                <div class="patra-ap-row">
                  <span class="patra-ap-k">{{
                    $t('OVERVIEW_REPORTS.OWNER_STATS.ESCALATION_RATE')
                  }}</span>
                  <span class="patra-ap-v patra-ap-warn patra-ap-empty">{{
                    emptyPlaceholder
                  }}</span>
                </div>
                <div class="patra-ap-row">
                  <span class="patra-ap-k">{{
                    $t('PATRA.REPORTS.RESOLVED')
                  }}</span>
                  <span class="patra-ap-v">{{ stats.resolved_today }}</span>
                </div>
                <div class="patra-ap-row">
                  <span class="patra-ap-k">{{
                    $t('PATRA.DASHBOARD.FLAGGED_REVIEW')
                  }}</span>
                  <span class="patra-ap-v">{{ stats.flagged_for_review }}</span>
                </div>
                <div class="patra-ap-sub">
                  {{ $t('OVERVIEW_REPORTS.OWNER_STATS.TOP_QUESTIONS') }}
                </div>
                <p class="patra-empty">
                  {{ $t('OVERVIEW_REPORTS.OWNER_STATS.NO_QUESTIONS') }}
                </p>
              </div>
            </div>
          </div>

          <div class="patra-card patra-card-full">
            <div class="patra-card-h">
              <div class="patra-card-t">
                <span class="patra-card-dot" />
                {{ $t('OVERVIEW_REPORTS.CONVERSATION_HEATMAP.HEADER') }}
                <span class="patra-card-t-muted">{{
                  heatmapPeriodSuffix
                }}</span>
              </div>
            </div>
            <div class="patra-heatmap">
              <div class="patra-hm-grid">
                <div />
                <div
                  v-for="hour in heatmapHours"
                  :key="`h-${hour}`"
                  class="patra-hm-col-lbl"
                >
                  {{ hour % 6 === 0 ? hour : '' }}
                </div>
                <template v-for="day in heatmapDays" :key="day">
                  <div class="patra-hm-row-lbl">{{ day }}</div>
                  <!-- TODO: wire backend -->
                  <div
                    v-for="hour in heatmapHours"
                    :key="`${day}-${hour}`"
                    class="patra-hm-cell"
                    @click="noopPlaceholder"
                  />
                </template>
              </div>
            </div>
            <div class="patra-hm-legend">
              {{ heatmapLess }}
              <span class="patra-hm-scale">
                <i class="patra-hm-scale-0" />
                <i class="patra-hm-scale-1" />
                <i class="patra-hm-scale-2" />
                <i class="patra-hm-scale-3" />
                <i class="patra-hm-scale-4" />
              </span>
              {{ heatmapMore }}
            </div>
            <p class="patra-empty patra-heatmap-empty-msg">
              {{ $t('OVERVIEW_REPORTS.CONVERSATION_HEATMAP.NO_CONVERSATIONS') }}
            </p>
          </div>

          <div class="patra-grid">
            <div class="patra-card">
              <div class="patra-card-h">
                <div class="patra-card-t">
                  <span class="patra-card-dot" />
                  {{ $t('PATRA.DASHBOARD.ACTIVE_AGENTS') }}
                </div>
                <span class="patra-card-more">{{ activeAgentsCount }}</span>
              </div>
              <ul v-if="stats.active_agents?.length" class="patra-agent-list">
                <!-- TODO: wire backend — agent drill-down -->
                <li
                  v-for="(agent, index) in stats.active_agents"
                  :key="agent.name"
                  class="patra-agent"
                  @click="noopPlaceholder"
                >
                  <div
                    class="patra-agent-ava"
                    :style="{ background: channelColor(index) }"
                  >
                    {{ agent.name.charAt(0) }}
                  </div>
                  <div class="patra-agent-info">
                    <div class="patra-agent-nm">{{ agent.name }}</div>
                    <div class="patra-agent-sub">{{ agent.role }}</div>
                  </div>
                  <span class="patra-role-pill online">{{
                    agentOnlineLabel
                  }}</span>
                </li>
              </ul>
              <p v-else class="patra-empty">
                {{ $t('PATRA.DASHBOARD.NO_AGENTS') }}
              </p>
            </div>

            <div class="patra-card patra-game-wrap">
              <div class="patra-card-h">
                <div class="patra-card-t">
                  <span class="patra-card-dot" />
                  {{ $t('GAME_HEALTH.TITLE') }}
                </div>
                <span
                  v-if="stats.game_performance"
                  class="patra-card-more patra-games-ok"
                >
                  {{ gamePerformanceCounts }} {{ gamesOkEmoji }}
                </span>
              </div>
              <GameHealthDashboard />
            </div>
          </div>

          <div class="patra-card patra-loads-footer">
            <div class="patra-lf-item">
              <div class="patra-lf-l">{{ $t('PATRA.REPORTS.LOADS') }}</div>
              <div class="patra-lf-v patra-lf-v-green">
                {{ loadsFooterLine }}
              </div>
            </div>
            <div class="patra-lf-div" />
            <div class="patra-lf-item">
              <div class="patra-lf-l">{{ $t('PATRA.REPORTS.CASHOUTS') }}</div>
              <div class="patra-lf-v">{{ cashoutsFooterLine }}</div>
            </div>
            <div class="patra-lf-div" />
            <div class="patra-lf-item">
              <div class="patra-lf-l">
                {{ $t('PATRA.DASHBOARD.NET_TODAY') }}
              </div>
              <div class="patra-lf-v patra-lf-v-purple">
                {{ formattedNetToday }}
              </div>
            </div>
          </div>
        </template>
      </div>
    </div>
  </div>
</template>

<style scoped>
.patra-owner-dashboard {
  --canvas: #050409;
  --surface: #0c0b12;
  --surface-2: #131119;
  --surface-3: #1b1925;
  --surface-4: #252233;
  --border: #171520;
  --border-hi: #2e2940;
  --patra: #6e56cf;
  --patra-2: #8b5cf6;
  --patra-3: #a78bfa;
  --patra-deep: #5b45b0;
  --patra-glow: rgba(110, 86, 207, 0.55);
  --text: #ededf2;
  --text-2: #a8a6b6;
  --text-3: #75727f;
  --text-4: #54515e;
  --green: #3fb950;
  --amber: #e3a008;
  --red: #f85149;
  --blue: #58a6ff;
  --pink: #ec4899;
  --cyan: #2aabee;
  --grid-line: rgba(255, 255, 255, 0.022);
  --inset: rgba(255, 255, 255, 0.045);
  --shadow: 0 24px 60px -20px rgba(0, 0, 0, 0.8);
  --mesh-1: rgba(110, 86, 207, 0.16);
  --mesh-2: rgba(139, 92, 246, 0.1);
  --mesh-3: rgba(236, 72, 153, 0.05);

  position: relative;
  width: 100%;
  height: 100%;
  min-height: 0;
  overflow-y: auto;
  overflow-x: hidden;
  background: var(--canvas);
  color: var(--text);
  font-family: Inter, ui-sans-serif, system-ui, sans-serif;
  font-size: 14px;
  -webkit-font-smoothing: antialiased;
}

.patra-spotlight {
  position: fixed;
  width: 460px;
  height: 460px;
  border-radius: 50%;
  background: radial-gradient(
    circle,
    rgba(110, 86, 207, 0.16),
    rgba(110, 86, 207, 0.04) 42%,
    transparent 66%
  );
  pointer-events: none;
  z-index: 0;
  transform: translate(-50%, -50%);
  opacity: 0;
  transition: opacity 0.5s;
  mix-blend-mode: screen;
  filter: blur(12px);
}

.patra-mesh {
  position: fixed;
  inset: 0;
  pointer-events: none;
  z-index: 0;
  overflow: hidden;
}

.patra-mesh::before,
.patra-mesh::after {
  content: '';
  position: absolute;
  border-radius: 50%;
  filter: blur(100px);
}

.patra-mesh::before {
  top: -15%;
  right: -5%;
  width: 700px;
  height: 560px;
  background:
    radial-gradient(circle at 40% 40%, var(--mesh-1), transparent 60%),
    radial-gradient(circle at 70% 70%, var(--mesh-2), transparent 60%);
  animation: patra-mesh-a 22s ease-in-out infinite alternate;
}

.patra-mesh::after {
  bottom: -20%;
  left: 10%;
  width: 560px;
  height: 500px;
  background: radial-gradient(
    circle at 50% 50%,
    var(--mesh-3),
    transparent 65%
  );
  animation: patra-mesh-b 28s ease-in-out infinite alternate;
}

.patra-main {
  position: relative;
  z-index: 1;
}

.patra-topbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 22px 30px 0;
}

.patra-topbar-title {
  font-family: 'Space Grotesk', Inter, ui-sans-serif, sans-serif;
  font-weight: 600;
  font-size: 26px;
  letter-spacing: -0.02em;
  color: var(--text);
}

.patra-topbar-sub {
  font-size: 13px;
  color: var(--text-3);
  margin-top: 3px;
}

.patra-tb-right {
  display: flex;
  align-items: center;
  gap: 10px;
}

.patra-range {
  display: flex;
  gap: 3px;
  background: var(--surface-2);
  border: 1px solid var(--border);
  border-radius: 10px;
  padding: 3px;
}

.patra-range-btn {
  font-size: 12px;
  font-weight: 500;
  padding: 6px 13px;
  border-radius: 7px;
  border: none;
  background: transparent;
  color: var(--text-3);
  cursor: pointer;
  transition: all 0.2s;
}

.patra-range-btn:hover {
  color: var(--text);
}

.patra-range-btn.active {
  background: linear-gradient(135deg, var(--patra), var(--patra-deep));
  color: #fff;
  box-shadow: 0 2px 8px var(--patra-glow);
}

.patra-btn {
  font-size: 13px;
  font-weight: 500;
  padding: 9px 15px;
  border-radius: 10px;
  border: 1px solid var(--border);
  background: var(--surface-2);
  color: var(--text);
  cursor: pointer;
  transition: all 0.22s cubic-bezier(0.23, 1, 0.32, 1);
  display: inline-flex;
  align-items: center;
  gap: 7px;
}

.patra-btn svg {
  width: 15px;
  height: 15px;
}

.patra-btn:hover {
  border-color: var(--border-hi);
  transform: translateY(-2px);
  box-shadow: 0 6px 16px rgba(0, 0, 0, 0.3);
}

.patra-content {
  padding: 22px 30px 40px;
}

.patra-loading {
  display: flex;
  justify-content: center;
  padding: 64px 0;
}

.patra-error {
  padding: 16px;
  border: 1px solid rgba(248, 81, 73, 0.4);
  border-radius: 12px;
  background: rgba(248, 81, 73, 0.08);
  color: #fca5a5;
  font-size: 0.875rem;
}

.patra-kpis {
  display: grid;
  grid-template-columns: repeat(5, 1fr);
  gap: 14px;
  margin-bottom: 18px;
}

.patra-kpi {
  padding: 18px;
  cursor: pointer;
}

.patra-kpi-top {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 14px;
}

.patra-kpi-ic-violet {
  background: rgba(139, 92, 246, 0.14);
}

.patra-kpi-ic-blue {
  background: rgba(88, 166, 255, 0.14);
}

.patra-kpi-ic-green {
  background: rgba(63, 185, 80, 0.14);
}

.patra-kpi-ic-red {
  background: rgba(248, 81, 73, 0.14);
}

.patra-leg-sw-ai {
  background: var(--patra-2);
}

.patra-leg-sw-amber {
  background: var(--amber);
}

.patra-leg-sw-muted {
  background: var(--surface-4);
}

.patra-hm-scale-0 {
  background: var(--surface-3);
}

.patra-hm-scale-1 {
  background: rgba(110, 86, 207, 0.3);
}

.patra-hm-scale-2 {
  background: rgba(110, 86, 207, 0.55);
}

.patra-hm-scale-3 {
  background: rgba(110, 86, 207, 0.8);
}

.patra-hm-scale-4 {
  background: var(--patra-2);
}

.patra-kpi-ic {
  width: 38px;
  height: 38px;
  border-radius: 11px;
  display: flex;
  align-items: center;
  justify-content: center;
}

.patra-kpi-ic svg {
  width: 19px;
  height: 19px;
}

.patra-kpi-n {
  font-family: 'Space Grotesk', Inter, ui-sans-serif, sans-serif;
  font-weight: 700;
  font-size: 30px;
  letter-spacing: -0.02em;
  line-height: 1;
  transition: transform 0.3s cubic-bezier(0.34, 1.56, 0.64, 1);
  display: inline-block;
}

.patra-kpi:hover .patra-kpi-n {
  transform: scale(1.06);
}

.patra-kpi-n-accent {
  background: linear-gradient(135deg, var(--patra-2), var(--patra-3));
  -webkit-background-clip: text;
  background-clip: text;
  -webkit-text-fill-color: transparent;
}

.patra-kpi-n-warn {
  color: var(--red);
}

.patra-kpi-n-green {
  color: var(--green);
}

.patra-kpi-l {
  font-size: 12px;
  color: var(--text-3);
  margin-top: 6px;
}

.patra-spark {
  margin-top: 12px;
  height: 30px;
  width: 100%;
}

.patra-grid {
  display: grid;
  grid-template-columns: 1.6fr 1fr;
  gap: 14px;
  margin-bottom: 14px;
}

.patra-card-full {
  margin-bottom: 14px;
}

.patra-card {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 16px;
  padding: 20px;
  position: relative;
  overflow: hidden;
  isolation: isolate;
  transition:
    transform 0.35s cubic-bezier(0.34, 1.56, 0.64, 1),
    box-shadow 0.35s,
    border-color 0.25s;
  animation: patra-m-in 0.5s cubic-bezier(0.23, 1, 0.32, 1) backwards;
}

.patra-card::before {
  content: '';
  position: absolute;
  inset: 0;
  border-radius: inherit;
  pointer-events: none;
  opacity: 0;
  transition: opacity 0.3s;
  background: radial-gradient(
    260px circle at var(--gx, 50%) var(--gy, 50%),
    rgba(110, 86, 207, 0.15),
    transparent 70%
  );
  z-index: -1;
}

.patra-card:hover::before {
  opacity: 1;
}

.patra-card:hover {
  transform: translateY(-4px) scale(1.008);
  box-shadow:
    0 18px 40px -14px rgba(0, 0, 0, 0.55),
    0 0 26px rgba(110, 86, 207, 0.18);
  border-color: var(--patra);
}

.patra-kpi {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 16px;
  position: relative;
  overflow: hidden;
  transition: all 0.3s cubic-bezier(0.34, 1.56, 0.64, 1);
  animation: patra-m-in 0.5s cubic-bezier(0.23, 1, 0.32, 1) backwards;
}

.patra-kpi::after {
  content: '';
  position: absolute;
  inset: 0;
  background: radial-gradient(
    180px circle at var(--mx, 50%) var(--my, 50%),
    rgba(110, 86, 207, 0.16),
    transparent 70%
  );
  opacity: 0;
  transition: opacity 0.3s;
  pointer-events: none;
}

.patra-kpi:hover {
  border-color: var(--patra);
  transform: translateY(-6px) scale(1.02);
  box-shadow:
    0 20px 40px -10px rgba(0, 0, 0, 0.5),
    0 0 26px rgba(110, 86, 207, 0.22);
}

.patra-kpi:hover::after {
  opacity: 1;
}

.patra-card-h {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 18px;
}

.patra-card-t {
  font-family: 'Space Grotesk', Inter, ui-sans-serif, sans-serif;
  font-weight: 600;
  font-size: 16px;
  display: flex;
  align-items: center;
  gap: 9px;
}

.patra-card-dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: var(--patra-2);
  box-shadow: 0 0 8px var(--patra-glow);
  flex-shrink: 0;
}

.patra-card-t-muted {
  font-weight: 400;
  color: var(--text-3);
  font-size: 13px;
}

.patra-card-more {
  color: var(--text-3);
  font-size: 12px;
}

.patra-card-more-btn {
  border: none;
  background: transparent;
  cursor: pointer;
  padding: 0;
}

.patra-card-more-btn:hover {
  color: var(--text);
}

.patra-games-ok {
  color: var(--green);
  font-family: 'JetBrains Mono', ui-monospace, monospace;
}

.patra-ch-row {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 12px 0;
  border-bottom: 1px solid var(--border);
}

.patra-ch-row:last-child {
  border: none;
}

.patra-ch-ic {
  width: 32px;
  height: 32px;
  border-radius: 9px;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}

.patra-ch-ic svg {
  width: 17px;
  height: 17px;
}

.patra-ch-info {
  flex: 1;
  min-width: 0;
}

.patra-ch-nm {
  font-size: 13px;
  font-weight: 500;
}

.patra-ch-bar {
  height: 5px;
  border-radius: 3px;
  background: var(--surface-3);
  margin-top: 5px;
  overflow: hidden;
}

.patra-ch-bar i {
  display: block;
  height: 100%;
  border-radius: 3px;
  animation: patra-ch-fill 1s cubic-bezier(0.23, 1, 0.32, 1) backwards;
}

.patra-ch-val {
  font-size: 13px;
  font-weight: 600;
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  flex-shrink: 0;
}

.patra-donut-wrap {
  display: flex;
  align-items: center;
  gap: 24px;
}

.patra-donut {
  position: relative;
  width: 150px;
  height: 150px;
  flex-shrink: 0;
}

.patra-donut svg {
  transform: rotate(-90deg);
}

.patra-donut-arc {
  animation: patra-donut-grow 1.4s cubic-bezier(0.23, 1, 0.32, 1);
}

.patra-donut-center {
  position: absolute;
  inset: 0;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
}

.patra-donut-pct {
  font-family: 'Space Grotesk', Inter, ui-sans-serif, sans-serif;
  font-weight: 700;
  font-size: 30px;
  background: linear-gradient(135deg, var(--patra-2), var(--patra-3));
  -webkit-background-clip: text;
  background-clip: text;
  -webkit-text-fill-color: transparent;
}

.patra-donut-lbl {
  font-size: 10px;
  color: var(--text-3);
  text-transform: uppercase;
  letter-spacing: 0.05em;
  font-family: 'JetBrains Mono', ui-monospace, monospace;
}

.patra-legend {
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.patra-leg {
  display: flex;
  align-items: center;
  gap: 10px;
  font-size: 13px;
}

.patra-leg-sw {
  width: 11px;
  height: 11px;
  border-radius: 4px;
  flex-shrink: 0;
}

.patra-leg-v {
  margin-left: auto;
  font-weight: 600;
  font-family: 'JetBrains Mono', ui-monospace, monospace;
}

.patra-mini-stats {
  display: grid;
  grid-template-columns: repeat(5, 1fr);
  gap: 9px;
}

.patra-ms {
  text-align: center;
  padding: 12px 6px;
  background: var(--canvas);
  border: 1px solid var(--border);
  border-radius: 11px;
  transition: all 0.25s cubic-bezier(0.34, 1.56, 0.64, 1);
}

.patra-ms:hover {
  border-color: var(--patra);
  transform: translateY(-3px);
  box-shadow: 0 10px 22px rgba(0, 0, 0, 0.3);
}

.patra-ms-n {
  font-family: 'Space Grotesk', Inter, ui-sans-serif, sans-serif;
  font-weight: 700;
  font-size: 22px;
}

.patra-ms-empty {
  color: var(--text-3);
}

.patra-ms-l {
  font-size: 10px;
  color: var(--text-3);
  margin-top: 3px;
  line-height: 1.3;
}

.patra-ap-row {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 11px 0;
  border-bottom: 1px solid var(--border);
  font-size: 13px;
}

.patra-ap-k {
  color: var(--text-2);
}

.patra-ap-v {
  font-family: 'Space Grotesk', Inter, ui-sans-serif, sans-serif;
  font-weight: 700;
  font-size: 18px;
}

.patra-ap-warn {
  color: var(--amber);
}

.patra-ap-empty {
  color: var(--text-3);
}

.patra-ap-sub {
  font-size: 11px;
  color: var(--text-3);
  text-transform: uppercase;
  letter-spacing: 0.05em;
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  margin: 14px 0 10px;
}

.patra-heatmap {
  overflow-x: auto;
}

.patra-hm-grid {
  display: grid;
  grid-template-columns: 32px repeat(24, 1fr);
  gap: 3px;
  min-width: 560px;
}

.patra-hm-cell {
  aspect-ratio: 1;
  border-radius: 3px;
  background: var(--surface-3);
  transition: all 0.15s;
  cursor: pointer;
}

.patra-hm-cell:hover {
  transform: scale(1.4);
  box-shadow: 0 0 10px var(--patra-glow);
  z-index: 2;
  border: 1px solid var(--patra-2);
}

.patra-hm-row-lbl {
  font-size: 10px;
  color: var(--text-3);
  display: flex;
  align-items: center;
  font-family: 'JetBrains Mono', ui-monospace, monospace;
}

.patra-hm-col-lbl {
  font-size: 9px;
  color: var(--text-4);
  text-align: center;
  font-family: 'JetBrains Mono', ui-monospace, monospace;
}

.patra-hm-legend {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 11px;
  color: var(--text-3);
  margin-top: 12px;
  justify-content: flex-end;
}

.patra-hm-scale {
  display: flex;
  gap: 2px;
}

.patra-hm-scale i {
  width: 14px;
  height: 11px;
  border-radius: 2px;
  display: block;
}

.patra-heatmap-empty-msg {
  margin-top: 12px;
}

.patra-agent-list {
  list-style: none;
  margin: 0;
  padding: 0;
}

.patra-agent {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 11px 0;
  border-bottom: 1px solid var(--border);
  transition: all 0.2s;
  border-radius: 8px;
  cursor: pointer;
}

.patra-agent:last-child {
  border: none;
}

.patra-agent:hover {
  background: var(--surface-2);
  padding-left: 8px;
  padding-right: 8px;
}

.patra-agent-ava {
  width: 34px;
  height: 34px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  font-family: 'Space Grotesk', Inter, ui-sans-serif, sans-serif;
  font-weight: 600;
  font-size: 14px;
  color: #fff;
  flex-shrink: 0;
}

.patra-agent-info {
  flex: 1;
  min-width: 0;
}

.patra-agent-nm {
  font-size: 13px;
  font-weight: 500;
}

.patra-agent-sub {
  font-size: 11px;
  color: var(--text-3);
  text-transform: capitalize;
}

.patra-role-pill {
  font-size: 10px;
  font-weight: 600;
  padding: 3px 9px;
  border-radius: 20px;
  text-transform: capitalize;
  flex-shrink: 0;
}

.patra-role-pill.online {
  background: rgba(63, 185, 80, 0.16);
  color: var(--green);
}

.patra-loads-footer {
  display: flex;
  align-items: center;
  justify-content: space-around;
}

.patra-lf-item {
  text-align: center;
  flex: 1;
}

.patra-lf-l {
  font-size: 11px;
  color: var(--text-3);
  text-transform: uppercase;
  letter-spacing: 0.05em;
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  margin-bottom: 8px;
}

.patra-lf-v {
  font-family: 'Space Grotesk', Inter, ui-sans-serif, sans-serif;
  font-weight: 700;
  font-size: 28px;
}

.patra-lf-v span {
  font-size: 13px;
  font-weight: 400;
  color: var(--text-3);
  font-family: Inter, ui-sans-serif, sans-serif;
}

.patra-lf-v-green {
  color: var(--green);
}

.patra-lf-v-purple {
  background: linear-gradient(135deg, var(--patra-2), var(--patra-3));
  -webkit-background-clip: text;
  background-clip: text;
  -webkit-text-fill-color: transparent;
}

.patra-lf-div {
  width: 1px;
  height: 50px;
  background: var(--border);
}

.patra-empty {
  font-size: 0.875rem;
  color: var(--text-3);
}

@keyframes patra-m-in {
  from {
    opacity: 0;
    transform: translateY(16px);
  }

  to {
    opacity: 1;
    transform: translateY(0);
  }
}

@keyframes patra-mesh-a {
  0% {
    transform: translate(0, 0) scale(1);
  }

  100% {
    transform: translate(-50px, 40px) scale(1.12) rotate(8deg);
  }
}

@keyframes patra-mesh-b {
  0% {
    transform: translate(0, 0) scale(1);
  }

  100% {
    transform: translate(40px, -30px) scale(1.1);
  }
}

@keyframes patra-ch-fill {
  from {
    width: 0 !important;
  }
}

@keyframes patra-donut-grow {
  from {
    stroke-dashoffset: 377;
  }
}

@media (max-width: 1200px) {
  .patra-kpis {
    grid-template-columns: repeat(2, 1fr);
  }

  .patra-grid {
    grid-template-columns: 1fr;
  }

  .patra-mini-stats {
    grid-template-columns: repeat(2, 1fr);
  }
}

@media (prefers-reduced-motion: reduce) {
  .patra-card,
  .patra-kpi,
  .patra-mesh::before,
  .patra-mesh::after {
    animation: none !important;
  }
}

.patra-checklist-wrap :deep(> div) {
  background: var(--surface) !important;
  border: 1px solid var(--border) !important;
  border-radius: 16px !important;
  padding: 20px !important;
  margin-bottom: 14px;
  box-shadow: var(--shadow) !important;
  animation: patra-m-in 0.5s cubic-bezier(0.23, 1, 0.32, 1) backwards;
}

.patra-checklist-wrap :deep(h2) {
  font-family: 'Space Grotesk', Inter, ui-sans-serif, sans-serif !important;
  font-weight: 600 !important;
  font-size: 16px !important;
  color: var(--text) !important;
}

.patra-checklist-wrap :deep(button) {
  color: var(--text-3) !important;
  cursor: pointer;
}

.patra-checklist-wrap :deep(button:hover) {
  color: var(--text) !important;
}

.patra-checklist-wrap :deep(ul) {
  display: grid !important;
  grid-template-columns: repeat(3, 1fr) !important;
  gap: 10px !important;
}

.patra-checklist-wrap :deep(li) {
  display: flex !important;
  align-items: center !important;
  gap: 9px !important;
  font-size: 13px !important;
  padding: 11px 13px !important;
  background: var(--canvas) !important;
  border: 1px solid var(--border) !important;
  border-radius: 11px !important;
  transition: all 0.25s cubic-bezier(0.34, 1.56, 0.64, 1) !important;
}

.patra-checklist-wrap :deep(li:hover) {
  border-color: var(--patra) !important;
  transform: translateY(-2px);
  box-shadow: 0 6px 16px rgba(0, 0, 0, 0.3);
}

.patra-checklist-wrap :deep(li span:last-child) {
  color: var(--text) !important;
}

.patra-checklist-wrap :deep(li span.line-through) {
  color: var(--text-3) !important;
}

.patra-game-wrap :deep(> div > .mb-3) {
  display: none !important;
}

.patra-game-wrap :deep(> div) {
  background: transparent !important;
  border: none !important;
  padding: 0 !important;
  box-shadow: none !important;
}

.patra-game-wrap :deep(ul) {
  max-height: 300px;
  overflow-y: auto;
  padding-right: 4px;
}

.patra-game-wrap :deep(li) {
  display: flex !important;
  align-items: center !important;
  gap: 10px !important;
  padding: 11px 13px !important;
  background: var(--canvas) !important;
  border: 1px solid var(--border) !important;
  border-radius: 11px !important;
  margin-bottom: 9px !important;
  transition: all 0.25s cubic-bezier(0.34, 1.56, 0.64, 1) !important;
  cursor: pointer;
}

.patra-game-wrap :deep(li:hover) {
  border-color: var(--patra) !important;
  transform: translateX(3px);
  box-shadow: -3px 0 0 var(--patra);
}

.patra-game-wrap :deep(li span) {
  color: var(--text) !important;
  font-size: 13px !important;
}

.patra-game-wrap :deep(p) {
  color: var(--text-3) !important;
}
</style>
