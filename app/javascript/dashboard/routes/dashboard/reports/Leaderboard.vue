<script setup>
import { computed, onMounted, ref } from 'vue';
import PatraReportsAPI from 'dashboard/api/patraReports';

const agents = ref([]);
const period = ref('week');
const loading = ref(true);

const PERIODS = ['today', 'week', 'month'];

/* Field names match Analytics::AgentPerformanceService exactly — the old
   template read `resolved`/`messages_today`, which the service never sent,
   so every agent showed 0. */
const handledFor = agent => agent.conversations_handled || 0;

const sortedAgents = computed(() =>
  [...agents.value].sort((a, b) => handledFor(b) - handledFor(a))
);

const totalHandled = computed(() =>
  sortedAgents.value.reduce((sum, agent) => sum + handledFor(agent), 0)
);

const totalLoads = computed(() =>
  sortedAgents.value.reduce((sum, agent) => sum + (agent.loads_count || 0), 0)
);

const initialFor = agent => (agent.name || '?').charAt(0).toUpperCase();

const fetchAgents = async () => {
  loading.value = true;
  try {
    const { data } = await PatraReportsAPI.get(period.value);
    agents.value = data.agent_performance || [];
  } catch (error) {
    agents.value = [];
  } finally {
    loading.value = false;
  }
};

const setPeriod = key => {
  if (period.value === key) return;
  period.value = key;
  fetchAgents();
};

onMounted(fetchAgents);
</script>

<template>
  <div class="flex flex-col gap-4 p-6 lb-page">
    <header class="flex items-start justify-between gap-4 flex-wrap">
      <div>
        <h1 class="text-2xl font-semibold text-n-slate-12 lb-display">
          {{ $t('PATRA.LEADERBOARD.TITLE') }}
        </h1>
        <p class="text-sm text-n-slate-11">
          {{ $t('PATRA.LEADERBOARD.SUBTITLE') }}
        </p>
      </div>
      <div class="lb-period">
        <button
          v-for="key in PERIODS"
          :key="key"
          type="button"
          class="lb-period-btn"
          :class="{ active: period === key }"
          @click="setPeriod(key)"
        >
          {{ $t(`PATRA.LEADERBOARD.PERIOD.${key.toUpperCase()}`) }}
        </button>
      </div>
    </header>

    <section v-if="sortedAgents.length" class="lb-kpis">
      <div class="lb-kpi">
        <div class="lb-kpi-n">{{ sortedAgents.length }}</div>
        <div class="lb-kpi-l">{{ $t('PATRA.LEADERBOARD.ACTIVE_AGENTS') }}</div>
      </div>
      <div class="lb-kpi">
        <div class="lb-kpi-n">{{ totalHandled }}</div>
        <div class="lb-kpi-l">{{ $t('PATRA.LEADERBOARD.TOTAL_RESOLVED') }}</div>
      </div>
      <div class="lb-kpi">
        <div class="lb-kpi-n">{{ totalLoads }}</div>
        <div class="lb-kpi-l">{{ $t('PATRA.LEADERBOARD.TOTAL_LOADS') }}</div>
      </div>
    </section>

    <section class="rounded-2xl border border-n-weak bg-n-solid-1 p-5 lb-card">
      <div class="lb-card-h">
        <span class="lb-card-dot" />
        <span class="lb-card-t">{{ $t('PATRA.LEADERBOARD.RANKINGS') }}</span>
      </div>
      <!-- patra-final 6b (G24): real loading + guided empty state, no bare "…" -->
      <p v-if="loading" class="py-6 text-center text-n-slate-11">
        {{ $t('PATRA.LEADERBOARD.LOADING') }}
      </p>
      <div
        v-else-if="!sortedAgents.length"
        class="py-10 text-center text-n-slate-11"
      >
        <div class="text-3xl mb-2 opacity-60">🏆</div>
        <p class="text-sm m-0">{{ $t('PATRA.LEADERBOARD.EMPTY') }}</p>
        <p class="text-xs text-n-slate-10 mt-1 m-0">
          {{ $t('PATRA.LEADERBOARD.EMPTY_HINT') }}
        </p>
      </div>
      <div v-else class="lb-rows">
        <div
          v-for="(agent, idx) in sortedAgents"
          :key="agent.name"
          class="lb-row"
        >
          <div class="lb-rank" :class="`lb-rank--${idx < 3 ? idx + 1 : 'x'}`">
            {{ idx + 1 }}
          </div>
          <div class="lb-ava">{{ initialFor(agent) }}</div>
          <div class="lb-info">
            <div class="lb-name">{{ agent.name }}</div>
            <div v-if="agent.avg_first_response_minutes != null" class="lb-sub">
              {{ $t('PATRA.LEADERBOARD.RESPONSE_TIME') }} ·
              {{ agent.avg_first_response_minutes }}m
            </div>
          </div>
          <div class="lb-right lb-metric">
            <div class="lb-count">
              {{ agent.csat_score != null ? agent.csat_score : '—' }}
            </div>
            <div class="lb-sub">{{ $t('PATRA.LEADERBOARD.CSAT') }}</div>
          </div>
          <div class="lb-right lb-metric">
            <div class="lb-count">{{ agent.loads_count || 0 }}</div>
            <div class="lb-sub">{{ $t('PATRA.LEADERBOARD.LOADS') }}</div>
          </div>
          <div class="lb-right lb-metric">
            <div class="lb-count">{{ handledFor(agent) }}</div>
            <div class="lb-sub">{{ $t('PATRA.LEADERBOARD.RESOLVED') }}</div>
          </div>
        </div>
      </div>
    </section>
  </div>
</template>

<style scoped>
/* B1: spec leaderboard treatment (PATRA_APP_final.html 'leaderboard' screen).
   All colors via theme-aware tokens — correct in both themes. */
.lb-page {
  color: var(--text, #1a1a24);
}

.lb-display {
  font-family: 'Space Grotesk', 'Inter', sans-serif;
  letter-spacing: -0.01em;
}

.lb-kpis {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(160px, 220px));
  gap: 14px;
}

.lb-kpi {
  background: var(--surface, #fff);
  border: 1px solid var(--border, #e5e3eb);
  border-radius: 16px;
  padding: 18px;
  transition: all 0.3s cubic-bezier(0.34, 1.56, 0.64, 1);
}

.lb-kpi:hover {
  border-color: var(--patra, #6e56cf);
  transform: translateY(-4px);
}

.lb-kpi-n {
  font-family: 'Space Grotesk', sans-serif;
  font-weight: 700;
  font-size: 30px;
  letter-spacing: -0.02em;
  line-height: 1;
}

.lb-kpi-l {
  font-size: 12px;
  color: var(--text-3, #75727f);
  margin-top: 6px;
}

.lb-card-h {
  display: flex;
  align-items: center;
  gap: 9px;
  margin-bottom: 14px;
}

.lb-card-dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: var(--patra-2, #8b5cf6);
  box-shadow: 0 0 8px var(--patra-glow, rgba(110, 86, 207, 0.35));
}

.lb-card-t {
  font-family: 'Space Grotesk', sans-serif;
  font-weight: 600;
  font-size: 16px;
}

.lb-rows {
  display: flex;
  flex-direction: column;
}

.lb-row {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 10px 8px;
  border-radius: 10px;
  transition: background 0.2s;
}

.lb-row:hover {
  background: var(--surface-2, #f2f0f7);
}

.lb-row + .lb-row {
  border-top: 1px solid var(--border, #e5e3eb);
}

.lb-rank {
  width: 26px;
  height: 26px;
  border-radius: 8px;
  display: flex;
  align-items: center;
  justify-content: center;
  font-family: 'Space Grotesk', sans-serif;
  font-weight: 700;
  font-size: 13px;
  flex-shrink: 0;
  background: var(--surface-3, #ece9f2);
  color: var(--text-3, #75727f);
}

.lb-rank--1 {
  background: linear-gradient(135deg, #e3a008, #b8820a);
  color: #fff;
}

.lb-rank--2 {
  background: var(--surface-4, #dddae5);
}

.lb-rank--3 {
  background: rgba(227, 160, 8, 0.18);
  color: var(--amber, #9a6700);
}

.lb-ava {
  width: 32px;
  height: 32px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  font-weight: 600;
  font-size: 13px;
  flex-shrink: 0;
  background: linear-gradient(
    135deg,
    var(--patra, #6e56cf),
    var(--patra-deep, #5b45b0)
  );
  color: #fff;
}

.lb-info {
  flex: 1;
  min-width: 0;
}

.lb-name {
  font-weight: 600;
  font-size: 13.5px;
}

.lb-sub {
  font-size: 11px;
  color: var(--text-3, #75727f);
}

.lb-right {
  text-align: right;
}

.lb-metric {
  min-width: 58px;
}

.lb-period {
  display: flex;
  gap: 6px;
}

.lb-period-btn {
  padding: 5px 12px;
  border-radius: 8px;
  border: 1px solid var(--border, #e5e3eb);
  background: var(--surface, #fff);
  color: var(--text-3, #75727f);
  font-size: 12px;
  font-weight: 600;
  cursor: pointer;
  transition:
    background 0.2s,
    color 0.2s;
}

.lb-period-btn.active {
  background: var(--patra, #6e56cf);
  border-color: var(--patra, #6e56cf);
  color: #fff;
}

.lb-count {
  font-family: 'Space Grotesk', sans-serif;
  font-weight: 700;
  font-size: 16px;
}
</style>
