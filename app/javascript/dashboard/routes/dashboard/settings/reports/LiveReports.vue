<script setup>
import { computed } from 'vue';
import { useStore } from 'vuex';
import ReportHeader from './components/ReportHeader.vue';
import ConversationHeatmapContainer from './components/heatmaps/ConversationHeatmapContainer.vue';
import ResolutionHeatmapContainer from './components/heatmaps/ResolutionHeatmapContainer.vue';
import AgentLiveReportContainer from './components/AgentLiveReportContainer.vue';
import TeamLiveReportContainer from './components/TeamLiveReportContainer.vue';
import StatsLiveReportsContainer from './components/StatsLiveReportsContainer.vue';
import OwnerStatsWidget from '../../components/widgets/OwnerStatsWidget.vue';
import { REPORTS_PERMISSIONS } from 'dashboard/constants/permissions';
import { getUserPermissions, hasPermissions } from 'dashboard/helper/permissionsHelper';

const store = useStore();

const canSeeOwnerStats = computed(() => {
  const user = store.getters.getCurrentUser;
  const accountId = store.getters.getCurrentAccountId;
  const permissions = getUserPermissions(user, accountId);
  return hasPermissions(['administrator', REPORTS_PERMISSIONS], permissions);
});
</script>

<template>
  <ReportHeader :header-title="$t('OVERVIEW_REPORTS.HEADER')" />
  <div class="flex flex-col gap-4 pb-6">
    <OwnerStatsWidget v-if="canSeeOwnerStats" />
    <StatsLiveReportsContainer />
    <ConversationHeatmapContainer />
    <ResolutionHeatmapContainer />
    <AgentLiveReportContainer />
    <TeamLiveReportContainer />
  </div>
</template>
