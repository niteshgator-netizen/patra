<script>
import { useAlert, useTrack } from 'dashboard/composables';
import BotMetrics from './components/BotMetrics.vue';
import ReportFilters from './components/ReportFilters.vue';
import { GROUP_BY_FILTER } from './constants';
import ReportContainer from './ReportContainer.vue';
import { REPORTS_EVENTS } from '../../../../helper/AnalyticsHelper/events';
import ReportHeader from './components/ReportHeader.vue';

export default {
  name: 'BotReports',
  components: {
    BotMetrics,
    ReportHeader,
    ReportFilters,
    ReportContainer,
  },
  data() {
    return {
      from: 0,
      to: 0,
      groupBy: GROUP_BY_FILTER[1],
      reportKeys: {
        BOT_RESOLUTION_COUNT: 'bot_resolutions_count',
        BOT_HANDOFF_COUNT: 'bot_handoffs_count',
      },
      businessHours: false,
    };
  },
  computed: {
    requestPayload() {
      return {
        from: this.from,
        to: this.to,
      };
    },
  },
  methods: {
    fetchAllData() {
      this.fetchBotSummary();
      this.fetchChartData();
    },
    fetchBotSummary() {
      try {
        this.$store.dispatch('fetchBotSummary', this.getRequestPayload());
      } catch {
        useAlert(this.$t('REPORT.SUMMARY_FETCHING_FAILED'));
      }
    },
    fetchChartData() {
      Object.keys(this.reportKeys).forEach(async key => {
        try {
          await this.$store.dispatch('fetchAccountReport', {
            metric: this.reportKeys[key],
            ...this.getRequestPayload(),
          });
        } catch {
          useAlert(this.$t('REPORT.DATA_FETCHING_FAILED'));
        }
      });
    },
    getRequestPayload() {
      const { from, to, groupBy, businessHours } = this;

      return {
        from,
        to,
        groupBy: groupBy?.period,
        businessHours,
      };
    },
    onFilterChange({ from, to, groupBy, businessHours }) {
      this.from = from;
      this.to = to;
      this.groupBy = groupBy;
      this.businessHours = businessHours;
      this.fetchAllData();

      useTrack(REPORTS_EVENTS.FILTER_REPORT, {
        filterValue: { from, to, groupBy, businessHours },
        reportType: 'bots',
      });
    },
  },
};
</script>

<template>
  <div class="pat-reports-wrap">
    <div class="pat-reports-main">
      <ReportHeader :header-title="$t('BOT_REPORTS.HEADER')" />
      <div class="flex flex-col gap-4">
        <ReportFilters
          :show-entity-filter="false"
          show-group-by
          :show-business-hours="false"
          @filter-change="onFilterChange"
        />

        <BotMetrics :filters="requestPayload" />
        <ReportContainer
          account-summary-key="getBotSummary"
          summary-fetching-key="getBotSummaryFetchingStatus"
          :group-by="groupBy"
          :report-keys="reportKeys"
        />
      </div>
    </div>
  </div>
</template>

<style scoped>
.pat-reports-wrap {
  --canvas: #050409;
  --surface: #0c0b12;
  --surface-2: #131119;
  --surface-3: #1b1925;
  --border: #171520;
  --border-hi: #2e2940;
  --patra: #6e56cf;
  --patra-3: #a78bfa;
  --text: #ededf2;
  --text-2: #a8a6b6;
  --text-3: #75727f;
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

.pat-reports-main {
  position: relative;
  z-index: 1;
}

.pat-reports-wrap :deep(.text-heading-1) {
  font-family: 'Space Grotesk', sans-serif;
  font-weight: 600;
  font-size: 23px;
  color: var(--text) !important;
}

.pat-reports-wrap :deep(section.flex.flex-col.gap-1) {
  padding-top: 22px;
  padding-bottom: 18px;
}

.pat-reports-wrap :deep(.text-n-slate-12) {
  color: var(--text) !important;
}

.pat-reports-wrap :deep(.text-n-slate-11) {
  color: var(--text-2) !important;
}

.pat-reports-wrap :deep(.text-n-slate-10) {
  color: var(--text-3) !important;
}

.pat-reports-wrap :deep(.text-3xl),
.pat-reports-wrap :deep(.text-xl) {
  font-family: 'Space Grotesk', sans-serif;
  font-weight: 700;
}

.pat-reports-wrap :deep(div:has(> .card-header)) {
  background: var(--surface) !important;
  border: 1px solid var(--border) !important;
  border-radius: 14px !important;
  box-shadow: 0 4px 24px rgba(0, 0, 0, 0.35) !important;
}

.pat-reports-wrap :deep(.rounded-xl.border.bg-n-solid-2),
.pat-reports-wrap :deep(.bg-n-solid-2) {
  background: var(--surface) !important;
  border-color: var(--border) !important;
}

.pat-reports-wrap :deep(.outline-n-container) {
  outline-color: var(--border) !important;
}

.pat-reports-wrap :deep(.border-n-weak),
.pat-reports-wrap :deep(.dark\:border-n-slate-6) {
  border-color: var(--border) !important;
}

.pat-reports-wrap :deep(.group-hover\:bg-n-alpha-2) {
  background: var(--surface-2) !important;
  border-color: var(--border-hi) !important;
  color: var(--text-2) !important;
}

.pat-reports-wrap :deep(.group:hover .group-hover\:bg-n-alpha-2) {
  background: var(--surface-3) !important;
  border-color: var(--patra) !important;
  color: var(--text) !important;
}

.pat-reports-wrap :deep(.h-72) {
  background: var(--surface-2);
  border-radius: 10px;
  border: 1px solid var(--border);
}
</style>
