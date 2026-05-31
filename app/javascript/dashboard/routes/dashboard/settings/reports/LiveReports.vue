<script setup>
import { computed, ref } from 'vue';
import { useStore } from 'vuex';
import ReportHeader from './components/ReportHeader.vue';
import ConversationHeatmapContainer from './components/heatmaps/ConversationHeatmapContainer.vue';
import ResolutionHeatmapContainer from './components/heatmaps/ResolutionHeatmapContainer.vue';
import AgentLiveReportContainer from './components/AgentLiveReportContainer.vue';
import TeamLiveReportContainer from './components/TeamLiveReportContainer.vue';
import StatsLiveReportsContainer from './components/StatsLiveReportsContainer.vue';
import OwnerStatsWidget from '../../components/widgets/OwnerStatsWidget.vue';
import { REPORTS_PERMISSIONS } from 'dashboard/constants/permissions';
import {
  getUserPermissions,
  hasPermissions,
} from 'dashboard/helper/permissionsHelper';

const store = useStore();
const spotlightRef = ref(null);

const canSeeOwnerStats = computed(() => {
  const user = store.getters.getCurrentUser;
  const accountId = store.getters.getCurrentAccountId;
  const permissions = getUserPermissions(user, accountId);
  return hasPermissions(['administrator', REPORTS_PERMISSIONS], permissions);
});

function onSpotlightMove(event) {
  const el = spotlightRef.value;
  if (!el) return;
  el.style.left = `${event.clientX}px`;
  el.style.top = `${event.clientY}px`;
  el.style.opacity = '1';
}

function onSpotlightLeave() {
  const el = spotlightRef.value;
  if (el) el.style.opacity = '0';
}
</script>

<template>
  <div
    class="pat-overview-wrap"
    @mousemove="onSpotlightMove"
    @mouseleave="onSpotlightLeave"
  >
    <div ref="spotlightRef" class="pat-overview-spotlight" aria-hidden="true" />
    <div class="pat-overview-mesh" aria-hidden="true" />

    <div class="pat-overview-main">
      <ReportHeader :header-title="$t('OVERVIEW_REPORTS.HEADER')" />
      <div class="pat-overview-content flex flex-col gap-4 pb-6">
        <OwnerStatsWidget v-if="canSeeOwnerStats" />
        <StatsLiveReportsContainer />
        <ConversationHeatmapContainer />
        <ResolutionHeatmapContainer />
        <AgentLiveReportContainer />
        <TeamLiveReportContainer />
      </div>
    </div>
  </div>
</template>

<style scoped>
.pat-overview-wrap {
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
  --red: #f85149;
  --blue: #58a6ff;
  --mesh-1: rgba(110, 86, 207, 0.16);
  --mesh-2: rgba(139, 92, 246, 0.1);
  --mesh-3: rgba(236, 72, 153, 0.05);

  position: relative;
  min-height: 100%;
  margin-left: -24px;
  margin-right: -24px;
  padding: 0 24px 24px;
  color: var(--text);
  font-family: 'Inter', sans-serif;
  background: var(--canvas);
  overflow: hidden;
}

.pat-overview-spotlight {
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

.pat-overview-mesh {
  position: fixed;
  inset: 0;
  pointer-events: none;
  z-index: 0;
  overflow: hidden;
}

.pat-overview-mesh::before,
.pat-overview-mesh::after {
  content: '';
  position: absolute;
  border-radius: 50%;
  filter: blur(100px);
}

.pat-overview-mesh::before {
  top: -15%;
  right: -5%;
  width: 700px;
  height: 560px;
  background:
    radial-gradient(circle at 40% 40%, var(--mesh-1), transparent 60%),
    radial-gradient(circle at 70% 70%, var(--mesh-2), transparent 60%);
  animation: patOverviewMeshA 22s ease-in-out infinite alternate;
}

.pat-overview-mesh::after {
  bottom: -20%;
  left: 10%;
  width: 560px;
  height: 500px;
  background: radial-gradient(
    circle at 50% 50%,
    var(--mesh-3),
    transparent 65%
  );
  animation: patOverviewMeshB 28s ease-in-out infinite alternate;
}

@keyframes patOverviewMeshA {
  0% {
    transform: translate(0, 0) scale(1);
  }
  100% {
    transform: translate(-50px, 40px) scale(1.12) rotate(8deg);
  }
}

@keyframes patOverviewMeshB {
  0% {
    transform: translate(0, 0) scale(1);
  }
  100% {
    transform: translate(40px, -30px) scale(1.1);
  }
}

.pat-overview-main {
  position: relative;
  z-index: 1;
}

.pat-overview-content {
  gap: 16px;
}

/* Header */
.pat-overview-wrap :deep(.text-heading-1) {
  font-family: 'Space Grotesk', sans-serif;
  font-weight: 600;
  font-size: 23px;
  color: var(--text) !important;
}

.pat-overview-wrap :deep(section.flex.flex-col.gap-1) {
  padding-top: 22px;
  padding-bottom: 18px;
}

/* Metric cards (MetricCard + OwnerStatsWidget shells) */
.pat-overview-wrap :deep(div:has(> .card-header)) {
  background: var(--surface) !important;
  border: 1px solid var(--border) !important;
  border-radius: 14px !important;
  box-shadow: 0 4px 24px rgba(0, 0, 0, 0.35) !important;
  outline: none !important;
  transition:
    border-color 0.25s,
    transform 0.25s,
    box-shadow 0.25s;
}

.pat-overview-wrap :deep(div:has(> .card-header):hover) {
  border-color: var(--patra) !important;
  transform: translateY(-2px);
  box-shadow:
    0 16px 32px -10px rgba(0, 0, 0, 0.5),
    0 0 22px rgba(110, 86, 207, 0.15) !important;
}

.pat-overview-wrap :deep(.rounded-xl.border.bg-n-solid-2) {
  background: var(--surface) !important;
  border-color: var(--border) !important;
  box-shadow: 0 4px 24px rgba(0, 0, 0, 0.35);
}

.pat-overview-wrap :deep(.card-header h5) {
  color: var(--text) !important;
  font-family: 'Space Grotesk', sans-serif;
}

.pat-overview-wrap :deep(.bg-n-teal-3) {
  background: rgba(63, 185, 80, 0.16) !important;
}

.pat-overview-wrap :deep(.text-n-teal-11) {
  color: var(--green) !important;
}

.pat-overview-wrap :deep(.bg-n-teal-9) {
  background: var(--green) !important;
}

/* KPI metric values */
.pat-overview-wrap :deep(.text-n-slate-12) {
  color: var(--text) !important;
}

.pat-overview-wrap :deep(.text-n-slate-11) {
  color: var(--text-2) !important;
}

.pat-overview-wrap :deep(.text-3xl) {
  font-family: 'Space Grotesk', sans-serif;
  font-weight: 700;
  font-variant-numeric: tabular-nums;
}

/* Owner stats inner cards */
.pat-overview-wrap :deep(.rounded-lg.border) {
  border-color: var(--border) !important;
}

.pat-overview-wrap :deep(.border-n-weak),
.pat-overview-wrap :deep(.dark\:border-n-slate-6) {
  border-color: var(--border) !important;
}

.pat-overview-wrap :deep(.bg-n-alpha-2) {
  background: var(--surface-2) !important;
}

.pat-overview-wrap :deep(.bg-n-solid-1) {
  background: var(--surface-2) !important;
}

.pat-overview-wrap :deep(.border-green-200\/80),
.pat-overview-wrap :deep(.dark\:border-green-900\/50) {
  border-color: rgba(63, 185, 80, 0.35) !important;
}

.pat-overview-wrap :deep(.bg-green-50\/40),
.pat-overview-wrap :deep(.dark\:bg-green-950\/20) {
  background: rgba(63, 185, 80, 0.1) !important;
}

.pat-overview-wrap :deep(.border-red-200\/80),
.pat-overview-wrap :deep(.dark\:border-red-900\/50) {
  border-color: rgba(248, 81, 73, 0.35) !important;
}

.pat-overview-wrap :deep(.bg-red-50\/40),
.pat-overview-wrap :deep(.dark\:bg-red-950\/20) {
  background: rgba(248, 81, 73, 0.1) !important;
}

.pat-overview-wrap :deep(.text-green-700),
.pat-overview-wrap :deep(.text-green-600) {
  color: var(--green) !important;
}

.pat-overview-wrap :deep(.text-red-700),
.pat-overview-wrap :deep(.text-red-600) {
  color: var(--red) !important;
}

.pat-overview-wrap :deep(.uppercase.tracking-wide) {
  color: var(--text-3) !important;
  font-family: 'JetBrains Mono', monospace;
  font-size: 11px;
  letter-spacing: 0.04em;
}

.pat-overview-wrap :deep(button.rounded-lg.border) {
  background: var(--surface-2);
  border-color: var(--border-hi) !important;
  color: var(--text);
  transition: all 0.2s;
}

.pat-overview-wrap :deep(button.rounded-lg.border:hover:not(:disabled)) {
  border-color: var(--patra) !important;
  background: var(--surface-3);
  color: var(--patra-3);
}

/* Filter / toolbar controls */
.pat-overview-wrap :deep(.group-hover\:bg-n-alpha-2) {
  background: var(--surface-2) !important;
  border-color: var(--border-hi) !important;
  color: var(--text-2) !important;
}

.pat-overview-wrap :deep(.group:hover .group-hover\:bg-n-alpha-2) {
  background: var(--surface-3) !important;
  border-color: var(--patra) !important;
  color: var(--text) !important;
}

/* Tables (agent + team) */
.pat-overview-wrap :deep(thead) {
  background: var(--surface-2) !important;
}

.pat-overview-wrap :deep(thead th) {
  color: var(--text-4) !important;
  font-family: 'JetBrains Mono', monospace;
  font-size: 11px;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  border-bottom: 1px solid var(--border);
}

.pat-overview-wrap :deep(tbody) {
  background: transparent;
}

.pat-overview-wrap :deep(tbody tr) {
  transition: background 0.2s;
}

.pat-overview-wrap :deep(tbody tr:hover) {
  background: var(--surface-2) !important;
}

.pat-overview-wrap :deep(tbody td) {
  color: var(--text);
  border-color: var(--border);
}

.pat-overview-wrap :deep(.divide-y) {
  border-color: var(--border);
}

.pat-overview-wrap :deep(.divide-y > *) {
  border-color: var(--border) !important;
}

/* Heatmap grid */
.pat-overview-wrap :deep(.animate-loader-pulse) {
  background: var(--surface-3) !important;
}

.pat-overview-wrap :deep(.bg-n-slate-3) {
  background: var(--surface-3) !important;
}

.pat-overview-wrap :deep(.bg-n-slate-2) {
  background: var(--surface-2) !important;
}

.pat-overview-wrap :deep(.border-n-container) {
  border-color: var(--border) !important;
}

.pat-overview-wrap :deep(.text-n-slate-6) {
  color: var(--text) !important;
}

/* Heatmap tooltip */
.pat-overview-wrap :deep(.fixed.z-50.bg-n-slate-12) {
  background: var(--surface-4) !important;
  border: 1px solid var(--border-hi);
  color: var(--text) !important;
  box-shadow: 0 8px 24px rgba(0, 0, 0, 0.5);
}

/* Loading spinners */
.pat-overview-wrap :deep(.items-center.flex.text-base) {
  color: var(--text-2);
}

/* Pagination */
.pat-overview-wrap :deep(select),
.pat-overview-wrap :deep(input[type='number']) {
  background: var(--surface-2);
  border: 1px solid var(--border);
  color: var(--text);
  border-radius: 8px;
}

.pat-overview-wrap :deep(select:focus),
.pat-overview-wrap :deep(input[type='number']:focus) {
  border-color: var(--patra);
  outline: none;
  box-shadow: 0 0 0 3px rgba(110, 86, 207, 0.11);
}

@media (prefers-reduced-motion: reduce) {
  .pat-overview-mesh::before,
  .pat-overview-mesh::after {
    animation: none !important;
  }
}
</style>
