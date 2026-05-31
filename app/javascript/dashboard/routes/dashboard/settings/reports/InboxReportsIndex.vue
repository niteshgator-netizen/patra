<script setup>
import { ref } from 'vue';
import ReportHeader from './components/ReportHeader.vue';
import SummaryReports from './components/SummaryReports.vue';
import V4Button from 'dashboard/components-next/button/Button.vue';

const summarReportsRef = ref(null);

const onDownloadClick = () => {
  summarReportsRef.value.downloadReports();
};
</script>

<template>
  <div class="pat-reports-wrap">
    <div class="pat-reports-main">
      <ReportHeader
        :header-title="$t('INBOX_REPORTS.HEADER')"
        :header-description="$t('INBOX_REPORTS.DESCRIPTION')"
      >
        <V4Button
          :label="$t('INBOX_REPORTS.DOWNLOAD_INBOX_REPORTS')"
          icon="i-ph-download-simple"
          size="sm"
          @click="onDownloadClick"
        />
      </ReportHeader>

      <SummaryReports
        ref="summarReportsRef"
        action-key="summaryReports/fetchInboxSummaryReports"
        getter-key="inboxes/getInboxes"
        fetch-items-key="inboxes/get"
        summary-key="summaryReports/getInboxSummaryReports"
        type="inbox"
      />
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
  --text-4: #54515e;

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

.pat-reports-wrap :deep(a.text-n-brand) {
  color: var(--patra-3) !important;
}
</style>
