<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useToggle } from '@vueuse/core';
import { useStoreGetters, useMapGetter } from 'dashboard/composables/store';

import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CampaignLayout from 'dashboard/components-next/Campaigns/CampaignLayout.vue';
import CampaignList from 'dashboard/components-next/Campaigns/Pages/CampaignPage/CampaignList.vue';
import LiveChatCampaignDialog from 'dashboard/components-next/Campaigns/Pages/CampaignPage/LiveChatCampaign/LiveChatCampaignDialog.vue';
import EditLiveChatCampaignDialog from 'dashboard/components-next/Campaigns/Pages/CampaignPage/LiveChatCampaign/EditLiveChatCampaignDialog.vue';
import ConfirmDeleteCampaignDialog from 'dashboard/components-next/Campaigns/Pages/CampaignPage/ConfirmDeleteCampaignDialog.vue';
import LiveChatCampaignEmptyState from 'dashboard/components-next/Campaigns/EmptyState/LiveChatCampaignEmptyState.vue';

const { t } = useI18n();
const getters = useStoreGetters();

const editLiveChatCampaignDialogRef = ref(null);
const confirmDeleteCampaignDialogRef = ref(null);
const selectedCampaign = ref(null);

const uiFlags = useMapGetter('campaigns/getUIFlags');
const isFetchingCampaigns = computed(() => uiFlags.value.isFetching);

const [showLiveChatCampaignDialog, toggleLiveChatCampaignDialog] = useToggle();

const liveChatCampaigns = computed(
  () => getters['campaigns/getLiveChatCampaigns'].value
);

const hasNoLiveChatCampaigns = computed(
  () => liveChatCampaigns.value?.length === 0 && !isFetchingCampaigns.value
);

const handleEdit = campaign => {
  selectedCampaign.value = campaign;
  editLiveChatCampaignDialogRef.value.dialogRef.open();
};
const handleDelete = campaign => {
  selectedCampaign.value = campaign;
  confirmDeleteCampaignDialogRef.value.dialogRef.open();
};
</script>

<template>
  <div class="pat-page-wrap">
    <div class="pat-page-main">
      <CampaignLayout
        :header-title="t('CAMPAIGN.LIVE_CHAT.HEADER_TITLE')"
        :button-label="t('CAMPAIGN.LIVE_CHAT.NEW_CAMPAIGN')"
        @click="toggleLiveChatCampaignDialog()"
        @close="toggleLiveChatCampaignDialog(false)"
      >
        <template #action>
          <LiveChatCampaignDialog
            v-if="showLiveChatCampaignDialog"
            @close="toggleLiveChatCampaignDialog(false)"
          />
        </template>

        <div
          v-if="isFetchingCampaigns"
          class="flex justify-center items-center py-10 text-n-slate-11"
        >
          <Spinner />
        </div>
        <CampaignList
          v-else-if="!hasNoLiveChatCampaigns"
          :campaigns="liveChatCampaigns"
          is-live-chat-type
          @edit="handleEdit"
          @delete="handleDelete"
        />
        <LiveChatCampaignEmptyState
          v-else
          :title="t('CAMPAIGN.LIVE_CHAT.EMPTY_STATE.TITLE')"
          :subtitle="t('CAMPAIGN.LIVE_CHAT.EMPTY_STATE.SUBTITLE')"
          class="pt-14"
        />
        <EditLiveChatCampaignDialog
          ref="editLiveChatCampaignDialogRef"
          :selected-campaign="selectedCampaign"
        />
        <ConfirmDeleteCampaignDialog
          ref="confirmDeleteCampaignDialogRef"
          :selected-campaign="selectedCampaign"
        />
      </CampaignLayout>
    </div>
  </div>
</template>

<style scoped>
.pat-page-wrap {
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

.pat-page-main {
  position: relative;
  z-index: 1;
}

.pat-page-wrap :deep(.text-heading-1),
.pat-page-wrap :deep(h1),
.pat-page-wrap :deep(h2) {
  color: var(--text) !important;
}

.pat-page-wrap :deep(.text-n-slate-12) {
  color: var(--text) !important;
}

.pat-page-wrap :deep(.text-n-slate-11) {
  color: var(--text-2) !important;
}

.pat-page-wrap :deep(.text-n-slate-10),
.pat-page-wrap :deep(.text-n-slate-9) {
  color: var(--text-3) !important;
}

.pat-page-wrap :deep(.text-n-slate-6),
.pat-page-wrap :deep(.text-n-slate-7),
.pat-page-wrap :deep(.text-n-slate-8) {
  color: var(--text-4) !important;
}

.pat-page-wrap :deep(.bg-n-surface-1),
.pat-page-wrap :deep(.bg-n-solid-1) {
  background: var(--canvas) !important;
}

.pat-page-wrap :deep(.bg-n-surface-2),
.pat-page-wrap :deep(.bg-n-solid-2),
.pat-page-wrap :deep(.bg-n-solid-3) {
  background: var(--surface) !important;
}

.pat-page-wrap :deep(.bg-n-alpha-1),
.pat-page-wrap :deep(.bg-n-alpha-2) {
  background: var(--surface-2) !important;
}

.pat-page-wrap :deep(.bg-n-slate-1),
.pat-page-wrap :deep(.bg-n-slate-2) {
  background: var(--surface-2) !important;
}

.pat-page-wrap :deep(.bg-n-slate-3) {
  background: var(--surface-3) !important;
}

.pat-page-wrap :deep(.rounded-xl.border),
.pat-page-wrap :deep(.rounded-lg.border) {
  border-color: var(--border) !important;
}

.pat-page-wrap :deep(.border-n-weak),
.pat-page-wrap :deep(.border-n-container),
.pat-page-wrap :deep(.outline-n-weak),
.pat-page-wrap :deep(.outline-n-container),
.pat-page-wrap :deep(.dark\:border-n-slate-6) {
  border-color: var(--border) !important;
  outline-color: var(--border) !important;
}

.pat-page-wrap :deep(.divide-y > *) {
  border-color: var(--border) !important;
}

.pat-page-wrap :deep(.group-hover\:bg-n-alpha-2) {
  background: var(--surface-2) !important;
  border-color: var(--border-hi) !important;
  color: var(--text-2) !important;
}

.pat-page-wrap :deep(.group:hover .group-hover\:bg-n-alpha-2) {
  background: var(--surface-3) !important;
  border-color: var(--patra) !important;
  color: var(--text) !important;
}

.pat-page-wrap :deep(thead) {
  background: var(--surface-2) !important;
}

.pat-page-wrap :deep(thead th) {
  color: var(--text-4) !important;
  border-bottom: 1px solid var(--border);
}

.pat-page-wrap :deep(tbody tr:hover) {
  background: var(--surface-2) !important;
}

.pat-page-wrap :deep(tbody td) {
  color: var(--text);
  border-color: var(--border);
}

.pat-page-wrap :deep(input),
.pat-page-wrap :deep(textarea),
.pat-page-wrap :deep(select) {
  background: var(--surface-2);
  border: 1px solid var(--border);
  color: var(--text);
  border-radius: 8px;
}

.pat-page-wrap :deep(input:focus),
.pat-page-wrap :deep(textarea:focus),
.pat-page-wrap :deep(select:focus) {
  border-color: var(--patra);
  outline: none;
  box-shadow: 0 0 0 3px rgba(110, 86, 207, 0.11);
}

.pat-page-wrap :deep(.text-n-teal-10),
.pat-page-wrap :deep(.text-n-teal-11) {
  color: var(--green) !important;
}

.pat-page-wrap :deep(.text-n-ruby-9),
.pat-page-wrap :deep(.text-n-ruby-10) {
  color: var(--red) !important;
}

.pat-page-wrap :deep(.fixed.z-50.bg-n-slate-12) {
  background: var(--surface-4) !important;
  border: 1px solid var(--border-hi);
  color: var(--text) !important;
}

.pat-page-wrap :deep(.animate-loader-pulse) {
  background: var(--surface-3) !important;
}
</style>
