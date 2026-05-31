<script setup>
import WootReports from './components/WootReports.vue';
</script>

<template>
  <div class="pat-reports-wrap">
    <div class="pat-reports-main">
      <WootReports
        key="inbox-reports"
        type="inbox"
        getter-key="inboxes/getInboxes"
        action-key="inboxes/get"
        :download-button-label="$t('INBOX_REPORTS.DOWNLOAD_INBOX_REPORTS')"
        :report-title="$t('INBOX_REPORTS.HEADER')"
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
.pat-reports-wrap :deep(.dark\:border-n-slate-6) {
  border-color: var(--border) !important;
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
