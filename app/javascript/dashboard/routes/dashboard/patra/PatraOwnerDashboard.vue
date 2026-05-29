<script setup>
import { computed, onMounted, onUnmounted, ref } from 'vue';
import PatraDashboardAPI from 'dashboard/api/patraDashboard';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import GameHealthDashboard from 'dashboard/components/widgets/GameHealthDashboard.vue';
import OnboardingChecklist from 'dashboard/components/widgets/OnboardingChecklist.vue';

const loading = ref(true);
const stats = ref(null);
const error = ref(null);
const rootRef = ref(null);
const emptyPlaceholder = '—';

const channelEntries = computed(() => {
  const volume = stats.value?.volume_by_channel || {};
  const max = Math.max(...Object.values(volume), 1);
  return Object.entries(volume).map(([name, count]) => ({
    name,
    count,
    pct: Math.round((count / max) * 100),
  }));
});

function formatPercent(value) {
  return `${value ?? 0}%`;
}

const formattedNetToday = computed(() => `$${stats.value?.net_today ?? 0}`);

const gamePerformanceCounts = computed(() => {
  const perf = stats.value?.game_performance;
  if (!perf) return '';
  return `${perf.active}/${perf.total}`;
});

function onMouseMove(event) {
  const el = rootRef.value;
  if (!el) return;
  const rect = el.getBoundingClientRect();
  el.style.setProperty('--mouse-x', `${event.clientX - rect.left}px`);
  el.style.setProperty('--mouse-y', `${event.clientY - rect.top}px`);
}

onMounted(async () => {
  try {
    const { data } = await PatraDashboardAPI.get();
    stats.value = data;
  } catch (e) {
    error.value = e.message || 'Failed to load dashboard';
  } finally {
    loading.value = false;
  }

  rootRef.value?.addEventListener('mousemove', onMouseMove);
});

onUnmounted(() => {
  rootRef.value?.removeEventListener('mousemove', onMouseMove);
});
</script>

<template>
  <div ref="rootRef" class="patra-owner-dashboard">
    <div class="patra-grid-bg" aria-hidden="true" />
    <div class="patra-mesh-bg" aria-hidden="true" />
    <div class="patra-cursor-glow" aria-hidden="true" />

    <div class="patra-inner">
      <header class="patra-header patra-rise">
        <h1 class="patra-title">
          {{ $t('PATRA.DASHBOARD.TITLE') }}
        </h1>
        <p class="patra-subtitle">
          {{ $t('PATRA.DASHBOARD.SUBTITLE') }}
        </p>
      </header>

      <div v-if="loading" class="patra-loading">
        <Spinner />
      </div>

      <p v-else-if="error" class="patra-error">
        {{ error }}
      </p>

      <template v-else-if="stats">
        <div class="patra-checklist-wrap patra-rise patra-rise-d1">
          <OnboardingChecklist />
        </div>

        <div class="patra-kpi-grid">
          <div class="patra-card patra-kpi patra-rise patra-rise-d2">
            <p class="patra-kpi-label">
              {{ $t('PATRA.DASHBOARD.CONVERSATIONS_TODAY') }}
            </p>
            <p class="patra-kpi-value">
              {{ stats.conversations_today }}
            </p>
          </div>
          <div class="patra-card patra-kpi patra-rise patra-rise-d3">
            <p class="patra-kpi-label">
              {{ $t('PATRA.DASHBOARD.MESSAGES_IN') }}
            </p>
            <p class="patra-kpi-value">
              {{ stats.messages_in_today }}
            </p>
          </div>
          <div class="patra-card patra-kpi patra-rise patra-rise-d4">
            <p class="patra-kpi-label">
              {{ $t('PATRA.DASHBOARD.MESSAGES_OUT') }}
            </p>
            <p class="patra-kpi-value">
              {{ stats.messages_out_today }}
            </p>
          </div>
          <div
            class="patra-card patra-kpi patra-kpi-accent patra-rise patra-rise-d5"
          >
            <p class="patra-kpi-label">
              {{ $t('PATRA.DASHBOARD.AI_HANDLE_RATE') }}
            </p>
            <p class="patra-kpi-value patra-kpi-value-accent">
              {{ formatPercent(stats.ai_handle_rate) }}
            </p>
          </div>
          <div class="patra-card patra-kpi patra-rise patra-rise-d6">
            <p class="patra-kpi-label">
              {{ $t('PATRA.DASHBOARD.NEW_CUSTOMERS') }}
            </p>
            <p class="patra-kpi-value">
              {{ stats.new_customers_today }}
            </p>
          </div>
          <div class="patra-card patra-kpi patra-rise patra-rise-d7">
            <p class="patra-kpi-label">
              {{ $t('PATRA.DASHBOARD.FLAGGED_REVIEW') }}
            </p>
            <p class="patra-kpi-value">
              {{ stats.flagged_for_review }}
            </p>
          </div>
          <div class="patra-card patra-kpi patra-rise patra-rise-d8">
            <p class="patra-kpi-label">
              {{ $t('PATRA.REPORTS.RESOLVED') }}
            </p>
            <p class="patra-kpi-value">
              {{ stats.resolved_today }}
            </p>
          </div>
          <div class="patra-card patra-kpi patra-rise patra-rise-d9">
            <p class="patra-kpi-label">
              {{ $t('PATRA.DASHBOARD.NET_TODAY') }}
            </p>
            <p class="patra-kpi-value">
              {{ formattedNetToday }}
            </p>
          </div>
        </div>

        <div class="patra-two-col">
          <div class="patra-card patra-rise patra-rise-d10">
            <h2 class="patra-section-title">
              {{ $t('PATRA.DASHBOARD.VOLUME_BY_CHANNEL') }}
            </h2>
            <div v-if="channelEntries.length" class="patra-channel-list">
              <div
                v-for="row in channelEntries"
                :key="row.name"
                class="patra-channel-row"
              >
                <div class="patra-channel-meta">
                  <span class="patra-channel-name">{{ row.name }}</span>
                  <span class="patra-channel-count">{{ row.count }}</span>
                </div>
                <div class="patra-bar-track">
                  <div
                    class="patra-bar-fill"
                    :style="{ width: `${row.pct}%` }"
                  />
                </div>
              </div>
            </div>
            <p v-else class="patra-empty">
              {{ $t('PATRA.DASHBOARD.NO_DATA') }}
            </p>
          </div>

          <div class="patra-card patra-rise patra-rise-d11">
            <h2 class="patra-section-title">
              {{ $t('PATRA.DASHBOARD.AI_HANDLE_RATE') }}
            </h2>
            <div class="patra-donut-wrap">
              <svg class="patra-donut" viewBox="0 0 36 36" aria-hidden="true">
                <circle
                  class="patra-donut-track"
                  cx="18"
                  cy="18"
                  r="15.915"
                  fill="none"
                  stroke-width="3"
                />
                <circle
                  class="patra-donut-fill"
                  cx="18"
                  cy="18"
                  r="15.915"
                  fill="none"
                  stroke-width="3"
                  pathLength="100"
                  :stroke-dasharray="`${stats.ai_handle_rate} 100`"
                  stroke-dashoffset="0"
                  transform="rotate(-90 18 18)"
                />
              </svg>
              <div class="patra-donut-center">
                <span class="patra-donut-value">
                  {{ formatPercent(stats.ai_handle_rate) }}
                </span>
              </div>
            </div>
          </div>
        </div>

        <div class="patra-card patra-rise patra-rise-d12">
          <h2 class="patra-section-title">
            {{ $t('OVERVIEW_REPORTS.OWNER_STATS.PLAYERS') }}
          </h2>
          <div class="patra-stat-strip">
            <div class="patra-stat-item">
              <span class="patra-stat-label">{{
                $t('OVERVIEW_REPORTS.OWNER_STATS.TOTAL_PLAYERS')
              }}</span>
              <span class="patra-stat-value patra-stat-empty">{{
                emptyPlaceholder
              }}</span>
            </div>
            <div class="patra-stat-item">
              <span class="patra-stat-label">{{
                $t('PATRA.DASHBOARD.NEW_CUSTOMERS')
              }}</span>
              <span class="patra-stat-value">{{
                stats.new_customers_today
              }}</span>
            </div>
            <div class="patra-stat-item">
              <span class="patra-stat-label">{{
                $t('OVERVIEW_REPORTS.OWNER_STATS.VIP')
              }}</span>
              <span class="patra-stat-value patra-stat-empty">{{
                emptyPlaceholder
              }}</span>
            </div>
            <div class="patra-stat-item">
              <span class="patra-stat-label">{{
                $t('OVERVIEW_REPORTS.OWNER_STATS.DORMANT')
              }}</span>
              <span class="patra-stat-value patra-stat-empty">{{
                emptyPlaceholder
              }}</span>
            </div>
            <div class="patra-stat-item">
              <span class="patra-stat-label">{{
                $t('OVERVIEW_REPORTS.OWNER_STATS.ACTIVE_NOW')
              }}</span>
              <span class="patra-stat-value patra-stat-empty">{{
                emptyPlaceholder
              }}</span>
            </div>
          </div>
        </div>

        <div class="patra-card patra-rise patra-rise-d13">
          <h2 class="patra-section-title">
            {{ $t('OVERVIEW_REPORTS.OWNER_STATS.AI_PERFORMANCE') }}
          </h2>
          <div class="patra-ai-grid">
            <div class="patra-ai-stat">
              <span class="patra-stat-label">{{
                $t('PATRA.DASHBOARD.AI_HANDLE_RATE')
              }}</span>
              <span class="patra-stat-value patra-stat-value-accent">
                {{ formatPercent(stats.ai_handle_rate) }}
              </span>
            </div>
            <div class="patra-ai-stat">
              <span class="patra-stat-label">{{
                $t('PATRA.REPORTS.RESOLVED')
              }}</span>
              <span class="patra-stat-value">{{ stats.resolved_today }}</span>
            </div>
            <div class="patra-ai-stat">
              <span class="patra-stat-label">{{
                $t('PATRA.DASHBOARD.FLAGGED_REVIEW')
              }}</span>
              <span class="patra-stat-value">{{
                stats.flagged_for_review
              }}</span>
            </div>
            <div class="patra-ai-stat">
              <span class="patra-stat-label">{{
                $t('OVERVIEW_REPORTS.OWNER_STATS.ESCALATION_RATE')
              }}</span>
              <span class="patra-stat-value patra-stat-empty">{{
                emptyPlaceholder
              }}</span>
            </div>
            <div class="patra-ai-stat">
              <span class="patra-stat-label">{{
                $t('OVERVIEW_REPORTS.OWNER_STATS.AVG_MSGS_AI_CONV')
              }}</span>
              <span class="patra-stat-value patra-stat-empty">{{
                emptyPlaceholder
              }}</span>
            </div>
            <div class="patra-ai-stat patra-ai-stat-wide">
              <span class="patra-stat-label">{{
                $t('OVERVIEW_REPORTS.OWNER_STATS.TOP_QUESTIONS')
              }}</span>
              <span class="patra-empty-inline">{{
                $t('OVERVIEW_REPORTS.OWNER_STATS.NO_QUESTIONS')
              }}</span>
            </div>
          </div>
        </div>

        <div class="patra-card patra-rise patra-rise-d14">
          <h2 class="patra-section-title">
            {{ $t('OVERVIEW_REPORTS.CONVERSATION_HEATMAP.HEADER') }}
          </h2>
          <div class="patra-heatmap-empty">
            <div class="patra-heatmap-grid" aria-hidden="true">
              <div v-for="n in 84" :key="n" class="patra-heatmap-cell" />
            </div>
            <p class="patra-empty">
              {{ $t('OVERVIEW_REPORTS.CONVERSATION_HEATMAP.NO_CONVERSATIONS') }}
            </p>
          </div>
        </div>

        <div class="patra-two-col">
          <div class="patra-card patra-rise patra-rise-d15">
            <h2 class="patra-section-title">
              {{ $t('PATRA.DASHBOARD.ACTIVE_AGENTS') }}
            </h2>
            <ul v-if="stats.active_agents?.length" class="patra-agent-list">
              <li
                v-for="agent in stats.active_agents"
                :key="agent.name"
                class="patra-agent-row"
              >
                <span class="patra-agent-avatar">{{
                  agent.name.charAt(0)
                }}</span>
                <span class="patra-agent-name">{{ agent.name }}</span>
                <span class="patra-agent-role">{{ agent.role }}</span>
              </li>
            </ul>
            <p v-else class="patra-empty">
              {{ $t('PATRA.DASHBOARD.NO_AGENTS') }}
            </p>
          </div>

          <div class="patra-game-wrap patra-rise patra-rise-d16">
            <div v-if="stats.game_performance" class="patra-game-badge">
              {{ gamePerformanceCounts }}
              {{ $t('PATRA.DASHBOARD.GAME_PERFORMANCE') }}
            </div>
            <GameHealthDashboard />
          </div>
        </div>

        <div class="patra-card patra-footer patra-rise patra-rise-d17">
          <p class="patra-footer-title">
            {{ $t('PATRA.DASHBOARD.LOADS_CASHOUTS') }}
          </p>
          <p class="patra-footer-detail">
            {{
              $t('PATRA.DASHBOARD.LOADS_CASHOUTS_DETAIL', {
                loads: stats.loads_today?.amount || 0,
                loadCount: stats.loads_today?.count || 0,
                cashouts: stats.cashouts_today?.amount || 0,
                cashoutCount: stats.cashouts_today?.count || 0,
              })
            }}
          </p>
        </div>
      </template>
    </div>
  </div>
</template>

<style scoped>
.patra-owner-dashboard {
  --canvas: #0b0a0f;
  --surface: #13121a;
  --surface-2: #1a1926;
  --surface-3: #232133;
  --border: #1e1b29;
  --border-hi: #3b3554;
  --patra: #6e56cf;
  --patra-2: #8b5cf6;
  --patra-deep: #5b45b0;
  --text: #ffffff;
  --zinc-400: #a1a1aa;
  --zinc-500: #71717a;
  --card-text: #d4d4d8;
  --grid-line: rgba(255, 255, 255, 0.03);
  --inset: rgba(255, 255, 255, 0.05);
  --mesh-1: rgba(110, 86, 207, 0.2);
  --mesh-2: rgba(139, 92, 246, 0.12);
  --mouse-x: 50%;
  --mouse-y: 20%;

  position: relative;
  width: 100%;
  min-height: 100%;
  overflow: hidden;
  background: var(--canvas);
  color: var(--text);
  font-family: Inter, ui-sans-serif, system-ui, sans-serif;
  -webkit-font-smoothing: antialiased;
}

.patra-grid-bg {
  position: absolute;
  inset: 0;
  z-index: 0;
  pointer-events: none;
  background-image:
    linear-gradient(to right, var(--grid-line) 1px, transparent 1px),
    linear-gradient(to bottom, var(--grid-line) 1px, transparent 1px);
  background-size: 40px 40px;
  mask-image: radial-gradient(
    ellipse 80% 50% at 50% 0%,
    black 40%,
    transparent 100%
  );
}

.patra-mesh-bg {
  position: absolute;
  top: -10%;
  left: 50%;
  z-index: 0;
  width: 1100px;
  height: 700px;
  pointer-events: none;
  border-radius: 50%;
  background:
    radial-gradient(circle at 30% 30%, var(--mesh-1), transparent 55%),
    radial-gradient(circle at 70% 60%, var(--mesh-2), transparent 55%);
  filter: blur(80px);
  transform: translateX(-50%);
  animation: patra-mesh 16s ease-in-out infinite alternate;
}

.patra-cursor-glow {
  position: absolute;
  left: var(--mouse-x);
  top: var(--mouse-y);
  z-index: 0;
  width: 520px;
  height: 520px;
  pointer-events: none;
  border-radius: 50%;
  background: radial-gradient(
    circle,
    rgba(110, 86, 207, 0.14),
    transparent 62%
  );
  filter: blur(40px);
  transform: translate(-50%, -50%);
  transition:
    left 0.12s ease-out,
    top 0.12s ease-out;
}

.patra-inner {
  position: relative;
  z-index: 1;
  display: flex;
  flex-direction: column;
  gap: 20px;
  width: 100%;
  max-width: 1280px;
  margin: 0 auto;
  padding: 24px;
}

.patra-header {
  margin-bottom: 4px;
}

.patra-title {
  font-family: 'Space Grotesk', Inter, ui-sans-serif, sans-serif;
  font-size: clamp(1.5rem, 3vw, 2rem);
  font-weight: 700;
  letter-spacing: -0.02em;
  color: var(--text);
}

.patra-subtitle {
  margin-top: 6px;
  font-size: 0.875rem;
  color: var(--zinc-400);
}

.patra-loading {
  display: flex;
  justify-content: center;
  padding: 64px 0;
}

.patra-error {
  padding: 16px;
  border: 1px solid rgba(239, 68, 68, 0.4);
  border-radius: 12px;
  background: rgba(239, 68, 68, 0.08);
  color: #fca5a5;
  font-size: 0.875rem;
}

.patra-card {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 16px;
  padding: 20px;
  box-shadow:
    0 24px 48px -24px rgba(0, 0, 0, 0.5),
    inset 0 1px 0 var(--inset);
  transition:
    transform 0.28s cubic-bezier(0.16, 1, 0.3, 1),
    border-color 0.28s ease,
    box-shadow 0.28s ease;
}

.patra-card:hover {
  transform: translateY(-4px) scale(1.01);
  border-color: var(--border-hi);
  box-shadow:
    0 20px 40px rgba(110, 86, 207, 0.18),
    inset 0 1px 0 var(--inset);
}

.patra-kpi-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 14px;
}

@media (min-width: 768px) {
  .patra-kpi-grid {
    grid-template-columns: repeat(4, minmax(0, 1fr));
  }
}

.patra-kpi {
  padding: 16px 18px;
}

.patra-kpi-accent {
  border-color: rgba(110, 86, 207, 0.45);
  background: linear-gradient(145deg, var(--surface), rgba(110, 86, 207, 0.08));
}

.patra-kpi-label {
  font-size: 0.6875rem;
  font-weight: 600;
  letter-spacing: 0.06em;
  text-transform: uppercase;
  color: var(--zinc-500);
}

.patra-kpi-value {
  margin-top: 8px;
  font-family: 'Space Grotesk', Inter, ui-sans-serif, sans-serif;
  font-size: 1.75rem;
  font-weight: 700;
  letter-spacing: -0.02em;
  color: var(--text);
  font-variant-numeric: tabular-nums;
}

.patra-kpi-value-accent {
  background: linear-gradient(135deg, var(--patra), var(--patra-2));
  -webkit-background-clip: text;
  background-clip: text;
  -webkit-text-fill-color: transparent;
}

.patra-two-col {
  display: grid;
  gap: 20px;
}

@media (min-width: 768px) {
  .patra-two-col {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }
}

.patra-section-title {
  margin-bottom: 16px;
  font-family: 'Space Grotesk', Inter, ui-sans-serif, sans-serif;
  font-size: 0.875rem;
  font-weight: 600;
  color: var(--text);
}

.patra-channel-list {
  display: flex;
  flex-direction: column;
  gap: 14px;
}

.patra-channel-meta {
  display: flex;
  justify-content: space-between;
  gap: 8px;
  margin-bottom: 6px;
  font-size: 0.75rem;
}

.patra-channel-name {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  color: var(--card-text);
}

.patra-channel-count {
  flex-shrink: 0;
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  color: var(--zinc-400);
}

.patra-bar-track {
  height: 8px;
  overflow: hidden;
  border-radius: 999px;
  background: var(--surface-3);
}

.patra-bar-fill {
  height: 100%;
  border-radius: 999px;
  background: linear-gradient(90deg, var(--patra), var(--patra-2));
  box-shadow: 0 0 12px rgba(110, 86, 207, 0.45);
  transition: width 0.6s cubic-bezier(0.16, 1, 0.3, 1);
}

.patra-donut-wrap {
  position: relative;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 12px 0;
}

.patra-donut {
  width: 160px;
  height: 160px;
}

.patra-donut-track {
  stroke: var(--surface-3);
}

.patra-donut-fill {
  stroke: var(--patra-2);
  stroke-linecap: round;
  filter: drop-shadow(0 0 8px rgba(139, 92, 246, 0.5));
  transition: stroke-dasharray 0.8s cubic-bezier(0.16, 1, 0.3, 1);
}

.patra-donut-center {
  position: absolute;
  inset: 0;
  display: flex;
  align-items: center;
  justify-content: center;
}

.patra-donut-value {
  font-family: 'Space Grotesk', Inter, ui-sans-serif, sans-serif;
  font-size: 1.75rem;
  font-weight: 700;
  background: linear-gradient(135deg, var(--patra), var(--patra-2));
  -webkit-background-clip: text;
  background-clip: text;
  -webkit-text-fill-color: transparent;
}

.patra-stat-strip {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 12px;
}

@media (min-width: 768px) {
  .patra-stat-strip {
    grid-template-columns: repeat(5, minmax(0, 1fr));
  }
}

.patra-stat-item,
.patra-ai-stat {
  display: flex;
  flex-direction: column;
  gap: 6px;
  padding: 12px;
  border: 1px solid var(--border);
  border-radius: 12px;
  background: var(--surface-2);
}

.patra-stat-label {
  font-size: 0.6875rem;
  font-weight: 500;
  letter-spacing: 0.04em;
  text-transform: uppercase;
  color: var(--zinc-500);
}

.patra-stat-value {
  font-family: 'Space Grotesk', Inter, ui-sans-serif, sans-serif;
  font-size: 1.375rem;
  font-weight: 700;
  color: var(--text);
  font-variant-numeric: tabular-nums;
}

.patra-stat-value-accent {
  background: linear-gradient(135deg, var(--patra), var(--patra-2));
  -webkit-background-clip: text;
  background-clip: text;
  -webkit-text-fill-color: transparent;
}

.patra-stat-empty {
  color: var(--zinc-500);
}

.patra-ai-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 12px;
}

@media (min-width: 768px) {
  .patra-ai-grid {
    grid-template-columns: repeat(3, minmax(0, 1fr));
  }
}

.patra-ai-stat-wide {
  grid-column: 1 / -1;
}

.patra-empty,
.patra-empty-inline {
  font-size: 0.875rem;
  color: var(--zinc-500);
}

.patra-empty-inline {
  margin-top: 4px;
}

.patra-heatmap-empty {
  display: flex;
  flex-direction: column;
  gap: 16px;
}

.patra-heatmap-grid {
  display: grid;
  grid-template-columns: repeat(12, minmax(0, 1fr));
  gap: 4px;
}

.patra-heatmap-cell {
  aspect-ratio: 1;
  border-radius: 4px;
  background: var(--surface-3);
  opacity: 0.45;
}

.patra-agent-list {
  display: flex;
  flex-direction: column;
  gap: 10px;
  list-style: none;
  margin: 0;
  padding: 0;
}

.patra-agent-row {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 10px 12px;
  border: 1px solid var(--border);
  border-radius: 12px;
  background: var(--surface-2);
  transition:
    border-color 0.2s ease,
    transform 0.2s ease;
}

.patra-agent-row:hover {
  border-color: var(--border-hi);
  transform: translateX(2px);
}

.patra-agent-avatar {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 32px;
  height: 32px;
  flex-shrink: 0;
  border-radius: 50%;
  background: linear-gradient(135deg, var(--patra), var(--patra-deep));
  font-family: 'Space Grotesk', Inter, ui-sans-serif, sans-serif;
  font-size: 0.75rem;
  font-weight: 600;
  color: #fff;
  box-shadow: 0 0 12px rgba(110, 86, 207, 0.4);
}

.patra-agent-name {
  flex: 1;
  font-size: 0.875rem;
  color: var(--card-text);
}

.patra-agent-role {
  padding: 4px 10px;
  border-radius: 999px;
  background: rgba(123, 157, 111, 0.12);
  border: 1px solid rgba(123, 157, 111, 0.3);
  font-size: 0.6875rem;
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  color: #9ecf8f;
  text-transform: capitalize;
}

.patra-game-wrap {
  position: relative;
}

.patra-game-badge {
  position: absolute;
  top: 12px;
  right: 12px;
  z-index: 2;
  padding: 4px 10px;
  border-radius: 999px;
  background: rgba(110, 86, 207, 0.15);
  border: 1px solid rgba(110, 86, 207, 0.35);
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  font-size: 0.625rem;
  color: var(--patra-2);
  letter-spacing: 0.02em;
}

.patra-footer {
  text-align: center;
  border-style: dashed;
  background: linear-gradient(145deg, var(--surface), rgba(110, 86, 207, 0.05));
}

.patra-footer-title {
  font-size: 0.875rem;
  font-weight: 600;
  color: var(--text);
}

.patra-footer-detail {
  margin-top: 6px;
  font-size: 0.75rem;
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  color: var(--zinc-400);
}

.patra-rise {
  opacity: 0;
  animation: patra-rise 0.65s cubic-bezier(0.16, 1, 0.3, 1) forwards;
}

.patra-rise-d1 {
  animation-delay: 0.04s;
}
.patra-rise-d2 {
  animation-delay: 0.08s;
}
.patra-rise-d3 {
  animation-delay: 0.1s;
}
.patra-rise-d4 {
  animation-delay: 0.12s;
}
.patra-rise-d5 {
  animation-delay: 0.14s;
}
.patra-rise-d6 {
  animation-delay: 0.16s;
}
.patra-rise-d7 {
  animation-delay: 0.18s;
}
.patra-rise-d8 {
  animation-delay: 0.2s;
}
.patra-rise-d9 {
  animation-delay: 0.22s;
}
.patra-rise-d10 {
  animation-delay: 0.24s;
}
.patra-rise-d11 {
  animation-delay: 0.26s;
}
.patra-rise-d12 {
  animation-delay: 0.28s;
}
.patra-rise-d13 {
  animation-delay: 0.3s;
}
.patra-rise-d14 {
  animation-delay: 0.32s;
}
.patra-rise-d15 {
  animation-delay: 0.34s;
}
.patra-rise-d16 {
  animation-delay: 0.36s;
}
.patra-rise-d17 {
  animation-delay: 0.38s;
}

@keyframes patra-rise {
  from {
    opacity: 0;
    transform: translateY(20px);
  }

  to {
    opacity: 1;
    transform: translateY(0);
  }
}

@keyframes patra-mesh {
  0% {
    transform: translateX(-50%) scale(1) rotate(0deg);
    opacity: 0.85;
  }

  50% {
    transform: translateX(-52%) scale(1.06) rotate(4deg);
    opacity: 1;
  }

  100% {
    transform: translateX(-48%) scale(1.03) rotate(-3deg);
    opacity: 0.9;
  }
}

.patra-checklist-wrap :deep(> div) {
  background: var(--surface) !important;
  border-color: var(--border) !important;
  border-radius: 16px !important;
  box-shadow: inset 0 1px 0 var(--inset) !important;
}

.patra-checklist-wrap :deep(h2) {
  color: var(--text) !important;
  font-family: 'Space Grotesk', Inter, ui-sans-serif, sans-serif !important;
}

.patra-checklist-wrap :deep(button) {
  color: var(--zinc-400) !important;
}

.patra-checklist-wrap :deep(button:hover) {
  color: var(--text) !important;
}

.patra-checklist-wrap :deep(li span:last-child) {
  color: var(--card-text) !important;
}

.patra-checklist-wrap :deep(li span.line-through) {
  color: var(--zinc-500) !important;
}

.patra-game-wrap :deep(> div) {
  background: var(--surface) !important;
  border-color: var(--border) !important;
  border-radius: 16px !important;
  box-shadow:
    0 24px 48px -24px rgba(0, 0, 0, 0.5),
    inset 0 1px 0 var(--inset) !important;
  transition:
    transform 0.28s cubic-bezier(0.16, 1, 0.3, 1),
    border-color 0.28s ease,
    box-shadow 0.28s ease;
}

.patra-game-wrap :deep(> div:hover) {
  transform: translateY(-4px) scale(1.01);
  border-color: var(--border-hi) !important;
  box-shadow:
    0 20px 40px rgba(110, 86, 207, 0.18),
    inset 0 1px 0 var(--inset) !important;
}

.patra-game-wrap :deep(h2) {
  color: var(--text) !important;
  font-family: 'Space Grotesk', Inter, ui-sans-serif, sans-serif !important;
}

.patra-game-wrap :deep(span),
.patra-game-wrap :deep(p),
.patra-game-wrap :deep(li) {
  color: var(--card-text) !important;
}

.patra-game-wrap :deep(li) {
  border-color: var(--border) !important;
}
</style>
