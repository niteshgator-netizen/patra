<script>
import { mapGetters } from 'vuex';
import { useAlert, useTrack } from 'dashboard/composables';
import CsatMetrics from './components/CsatMetrics.vue';
import CsatTable from './components/CsatTable.vue';
import CsatFilters from './components/Csat/CsatFilters.vue';
import { generateFileName } from '../../../../helper/downloadHelper';
import { REPORTS_EVENTS } from '../../../../helper/AnalyticsHelper/events';
import { FEATURE_FLAGS } from '../../../../featureFlags';
import V4Button from 'dashboard/components-next/button/Button.vue';
import ReportHeader from './components/ReportHeader.vue';

export default {
  name: 'CsatResponses',
  components: {
    CsatMetrics,
    CsatTable,
    CsatFilters,
    ReportHeader,
    V4Button,
  },
  data() {
    return {
      pageIndex: 0,
      from: 0,
      to: 0,
      userIds: [],
      inbox: null,
      team: null,
      rating: null,
    };
  },
  computed: {
    ...mapGetters({
      accountId: 'getCurrentAccountId',
      isFeatureEnabledOnAccount: 'accounts/isFeatureEnabledonAccount',
    }),
    requestPayload() {
      return {
        from: this.from,
        to: this.to,
        user_ids: this.userIds,
        inbox_id: this.inbox,
        team_id: this.team,
        rating: this.rating,
      };
    },
    isTeamsEnabled() {
      return this.isFeatureEnabledOnAccount(
        this.accountId,
        FEATURE_FLAGS.TEAM_MANAGEMENT
      );
    },
  },
  mounted() {
    this.$store.dispatch('agents/get');
  },
  methods: {
    getAllData() {
      try {
        this.$store.dispatch('csat/getMetrics', this.requestPayload);
        this.getResponses();
      } catch {
        useAlert(this.$t('REPORT.DATA_FETCHING_FAILED'));
      }
    },
    getResponses() {
      this.$store.dispatch('csat/get', {
        page: this.pageIndex + 1,
        ...this.requestPayload,
      });
    },
    downloadReports() {
      const type = 'csat';
      try {
        this.$store.dispatch('csat/downloadCSATReports', {
          fileName: generateFileName({ type, to: this.to }),
          ...this.requestPayload,
        });
      } catch (error) {
        useAlert(this.$t('REPORT.CSAT_REPORTS.DOWNLOAD_FAILED'));
      }
    },
    onPageNumberChange(pageIndex) {
      this.pageIndex = pageIndex;
      this.getResponses();
    },
    onFilterChange({
      from,
      to,
      selectedAgents,
      selectedInbox,
      selectedTeam,
      selectedRating,
    }) {
      // do not track filter change on initial load
      if (this.from !== 0 && this.to !== 0) {
        useTrack(REPORTS_EVENTS.FILTER_REPORT, {
          filterType: 'date',
          reportType: 'csat',
        });
      }

      this.from = from;
      this.to = to;
      this.userIds = selectedAgents.map(el => el.id);
      this.inbox = selectedInbox?.id;
      this.team = selectedTeam?.id;
      this.rating = selectedRating?.value;

      this.getAllData();
    },
  },
};
</script>

<template>
  <div class="pat-reports-wrap">
    <div class="pat-reports-main">
      <ReportHeader :header-title="$t('CSAT_REPORTS.HEADER')">
        <V4Button
          :label="$t('CSAT_REPORTS.DOWNLOAD')"
          icon="i-ph-download-simple"
          size="sm"
          @click="downloadReports"
        />
      </ReportHeader>

      <div class="flex flex-col gap-6">
        <CsatFilters
          :show-team-filter="isTeamsEnabled"
          @filter-change="onFilterChange"
        />
        <CsatMetrics :filters="requestPayload" />
        <CsatTable :page-index="pageIndex" @page-change="onPageNumberChange" />
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

.pat-reports-wrap :deep(div:has(> .card-header)) {
  background: var(--surface) !important;
  border: 1px solid var(--border) !important;
  border-radius: 14px !important;
  box-shadow: 0 4px 24px rgba(0, 0, 0, 0.35) !important;
}

.pat-reports-wrap :deep(.rounded-xl.border),
.pat-reports-wrap :deep(.bg-n-solid-1),
.pat-reports-wrap :deep(.bg-n-solid-2) {
  background: var(--surface) !important;
  border-color: var(--border) !important;
}

.pat-reports-wrap :deep(.border-n-weak),
.pat-reports-wrap :deep(.dark\:border-n-slate-6) {
  border-color: var(--border) !important;
}

.pat-reports-wrap :deep(.bg-n-alpha-2) {
  background: var(--surface-2) !important;
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

.pat-reports-wrap :deep(thead) {
  background: var(--surface-2) !important;
}

.pat-reports-wrap :deep(thead th) {
  color: var(--text-4) !important;
  font-family: 'JetBrains Mono', monospace;
  font-size: 11px;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  border-bottom: 1px solid var(--border);
}

.pat-reports-wrap :deep(tbody tr:hover) {
  background: var(--surface-3) !important;
}

.pat-reports-wrap :deep(tbody td) {
  color: var(--text);
  border-color: var(--border);
}

.pat-reports-wrap :deep(.divide-y > *) {
  border-color: var(--border) !important;
}

.pat-reports-wrap :deep(select),
.pat-reports-wrap :deep(input[type='number']) {
  background: var(--surface-2);
  border: 1px solid var(--border);
  color: var(--text);
  border-radius: 8px;
}
</style>
