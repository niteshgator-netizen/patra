<script setup>
import { computed } from 'vue';
import ReportHeader from './components/ReportHeader.vue';
import ConversationHeatmapContainer from './components/heatmaps/ConversationHeatmapContainer.vue';
import ResolutionHeatmapContainer from './components/heatmaps/ResolutionHeatmapContainer.vue';
import AgentLiveReportContainer from './components/AgentLiveReportContainer.vue';
import TeamLiveReportContainer from './components/TeamLiveReportContainer.vue';
import StatsLiveReportsContainer from './components/StatsLiveReportsContainer.vue';
import OwnerStatsWidget from '../../components/widgets/OwnerStatsWidget.vue';
import { useMapGetter } from 'dashboard/composables/store';

const currentRole = useMapGetter('getCurrentRole');
const isAdministrator = computed(() => currentRole.value === 'administrator');
</script>

<template>
  <ReportHeader :header-title="$t('OVERVIEW_REPORTS.HEADER')" />
  <div class="flex flex-col gap-4 pb-6">
    <OwnerStatsWidget v-if="isAdministrator" />
    <StatsLiveReportsContainer />
    <ConversationHeatmapContainer />
    <ResolutionHeatmapContainer />
    <AgentLiveReportContainer />
    <TeamLiveReportContainer />
  </div>
</template>
