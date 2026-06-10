<script setup>
import SLAMetricCard from './SLAMetricCard.vue';
defineProps({
  hitRate: {
    type: String,
    required: true,
  },
  noOfBreaches: {
    type: Number,
    required: true,
  },
  noOfConversations: {
    type: Number,
    required: true,
  },
  isLoading: {
    type: Boolean,
    default: false,
  },
});
</script>

<template>
  <div class="pat-rep-grid grid w-full grid-cols-1 gap-4 sm:grid-cols-3">
    <SLAMetricCard
      :label="$t('SLA_REPORTS.METRICS.HIT_RATE.LABEL')"
      :value="hitRate"
      :tool-tip="$t('SLA_REPORTS.METRICS.HIT_RATE.TOOLTIP')"
      :is-loading="isLoading"
      class="pat-rep-card report-card"
    />

    <SLAMetricCard
      :label="$t('SLA_REPORTS.METRICS.NO_OF_MISSES.LABEL')"
      :value="noOfBreaches"
      :tool-tip="$t('SLA_REPORTS.METRICS.NO_OF_MISSES.TOOLTIP')"
      :is-loading="isLoading"
      class="pat-rep-card report-card"
    />
    <SLAMetricCard
      :label="$t('SLA_REPORTS.METRICS.NO_OF_CONVERSATIONS.LABEL')"
      :value="noOfConversations"
      :tool-tip="$t('SLA_REPORTS.METRICS.NO_OF_CONVERSATIONS.TOOLTIP')"
      :is-loading="isLoading"
      class="pat-rep-card report-card"
    />
  </div>
</template>
