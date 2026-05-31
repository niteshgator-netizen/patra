<script>
import V4Button from 'dashboard/components-next/button/Button.vue';
import { useAlert, useTrack } from 'dashboard/composables';
import ReportFilters from './components/ReportFilters.vue';
import { GROUP_BY_FILTER } from './constants';
import { REPORTS_EVENTS } from '../../../../helper/AnalyticsHelper/events';
import { generateFileName } from 'dashboard/helper/downloadHelper';
import ReportContainer from './ReportContainer.vue';
import ReportHeader from './components/ReportHeader.vue';

const REPORTS_KEYS = {
  CONVERSATIONS: 'conversations_count',
  INCOMING_MESSAGES: 'incoming_messages_count',
  OUTGOING_MESSAGES: 'outgoing_messages_count',
  FIRST_RESPONSE_TIME: 'avg_first_response_time',
  RESOLUTION_TIME: 'avg_resolution_time',
  RESOLUTION_COUNT: 'resolutions_count',
  REPLY_TIME: 'reply_time',
};

export default {
  name: 'ConversationReports',
  components: {
    ReportHeader,
    ReportFilters,
    ReportContainer,
    V4Button,
  },
  data() {
    return {
      from: 0,
      to: 0,
      groupBy: GROUP_BY_FILTER[1],
      businessHours: false,
    };
  },
  methods: {
    fetchAllData() {
      this.fetchAccountSummary();
      this.fetchChartData();
    },
    fetchAccountSummary() {
      try {
        this.$store.dispatch('fetchAccountSummary', this.getRequestPayload());
      } catch {
        useAlert(this.$t('REPORT.SUMMARY_FETCHING_FAILED'));
      }
    },
    fetchChartData() {
      [
        'CONVERSATIONS',
        'INCOMING_MESSAGES',
        'OUTGOING_MESSAGES',
        'FIRST_RESPONSE_TIME',
        'RESOLUTION_TIME',
        'RESOLUTION_COUNT',
        'REPLY_TIME',
      ].forEach(async key => {
        try {
          await this.$store.dispatch('fetchAccountReport', {
            metric: REPORTS_KEYS[key],
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
    downloadConversationReports() {
      const { from, to } = this;
      const fileName = generateFileName({
        type: 'conversation',
        to,
        businessHours: this.businessHours,
      });
      this.$store.dispatch('downloadConversationsSummaryReports', {
        from,
        to,
        fileName,
        businessHours: this.businessHours,
      });
    },
    onFilterChange({ from, to, groupBy, businessHours }) {
      this.from = from;
      this.to = to;
      this.groupBy = groupBy;
      this.businessHours = businessHours;
      this.fetchAllData();

      useTrack(REPORTS_EVENTS.FILTER_REPORT, {
        filterValue: { from, to, groupBy, businessHours },
        reportType: 'conversations',
      });
    },
  },
};
</script>

<template>
  <div class="pat-reports-wrap">
    <div class="pat-reports-main">
      <ReportHeader :header-title="$t('REPORT.HEADER')">
        <V4Button
          :label="$t('REPORT.DOWNLOAD_CONVERSATION_REPORTS')"
          icon="i-ph-download-simple"
          size="sm"
          @click="downloadConversationReports"
        />
      </ReportHeader>
      <div class="flex flex-col">
        <ReportFilters
          :show-entity-filter="false"
          show-group-by
          @filter-change="onFilterChange"
        />
        <ReportContainer :group-by="groupBy" />
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
  font-variant-numeric: tabular-nums;
}

.pat-reports-wrap :deep(.rounded-xl.border.bg-n-solid-2),
.pat-reports-wrap :deep(.bg-n-solid-2) {
  background: var(--surface) !important;
  border-color: var(--border) !important;
  box-shadow: 0 4px 24px rgba(0, 0, 0, 0.35);
}

.pat-reports-wrap :deep(.outline-n-container) {
  outline-color: var(--border) !important;
}

.pat-reports-wrap :deep(.border-n-weak),
.pat-reports-wrap :deep(.dark\:border-n-slate-6),
.pat-reports-wrap :deep(.border-n-container) {
  border-color: var(--border) !important;
}

.pat-reports-wrap :deep(.bg-n-alpha-2) {
  background: var(--surface-2) !important;
}

.pat-reports-wrap :deep(.text-n-teal-10) {
  color: var(--green) !important;
}

.pat-reports-wrap :deep(.border-n-teal-10) {
  border-color: var(--green) !important;
}

.pat-reports-wrap :deep(.text-n-ruby-9),
.pat-reports-wrap :deep(.text-n-ruby-10) {
  color: var(--red) !important;
}

.pat-reports-wrap :deep(.border-n-ruby-9) {
  border-color: var(--red) !important;
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
