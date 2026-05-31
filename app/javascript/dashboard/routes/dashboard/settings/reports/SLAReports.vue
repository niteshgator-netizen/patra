<script>
import V4Button from 'dashboard/components-next/button/Button.vue';
import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import SLAMetrics from './components/SLA/SLAMetrics.vue';
import SLATable from './components/SLA/SLATable.vue';
import SLAReportFilters from './components/SLA/SLAReportFilters.vue';
import { generateFileName } from 'dashboard/helper/downloadHelper';
import ReportHeader from './components/ReportHeader.vue';
export default {
  name: 'SLAReports',
  components: {
    V4Button,
    ReportHeader,
    SLAMetrics,
    SLATable,
    SLAReportFilters,
  },
  data() {
    return {
      pageNumber: 1,
      activeFilter: {
        from: 0,
        to: 0,
        assigned_agent_id: null,
        inbox_id: null,
        team_id: null,
        sla_policy_id: null,
        label_list: null,
      },
    };
  },
  computed: {
    ...mapGetters({
      slaReports: 'slaReports/getAll',
      slaMetrics: 'slaReports/getMetrics',
      slaMeta: 'slaReports/getMeta',
      uiFlags: 'slaReports/getUIFlags',
    }),
  },
  mounted() {
    this.$store.dispatch('agents/get');
    this.$store.dispatch('inboxes/get');
    this.$store.dispatch('teams/get');
    this.$store.dispatch('labels/get');
    this.$store.dispatch('sla/get');
    this.fetchSLAMetrics();
    this.fetchSLAReports();
  },
  methods: {
    fetchSLAReports({ pageNumber } = {}) {
      this.$store.dispatch('slaReports/get', {
        page: pageNumber || this.pageNumber,
        ...this.activeFilter,
      });
    },
    fetchSLAMetrics() {
      this.$store.dispatch('slaReports/getMetrics', this.activeFilter);
    },
    onPageChange(pageNumber) {
      this.fetchSLAReports({ pageNumber });
    },
    onFilterChange(params) {
      this.activeFilter = params;
      this.fetchSLAReports();
      this.fetchSLAMetrics();
    },
    downloadReports() {
      const type = 'sla';
      try {
        this.$store.dispatch('slaReports/download', {
          fileName: generateFileName({ type, to: this.activeFilter.to }),
          ...this.activeFilter,
        });
      } catch (error) {
        useAlert(this.$t('SLA_REPORTS.DOWNLOAD_FAILED'));
      }
    },
  },
};
</script>

<template>
  <div class="pat-reports-wrap">
    <div class="pat-reports-main">
      <ReportHeader :header-title="$t('SLA_REPORTS.HEADER')">
        <V4Button
          :label="$t('SLA_REPORTS.DOWNLOAD_SLA_REPORTS')"
          icon="i-ph-download-simple"
          size="sm"
          @click="downloadReports"
        />
      </ReportHeader>
      <div class="flex flex-col flex-1 gap-6">
        <SLAReportFilters @filter-change="onFilterChange" />
        <SLAMetrics
          :hit-rate="slaMetrics.hitRate"
          :no-of-breaches="slaMetrics.numberOfSLAMisses"
          :no-of-conversations="slaMetrics.numberOfConversations"
          :is-loading="uiFlags.isFetchingMetrics"
        />
        <SLATable
          :sla-reports="slaReports"
          :is-loading="uiFlags.isFetching"
          :current-page="Number(slaMeta.currentPage)"
          :total-count="Number(slaMeta.count)"
          @page-change="onPageChange"
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
