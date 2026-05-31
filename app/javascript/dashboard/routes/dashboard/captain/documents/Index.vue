<script setup>
import { computed, onMounted, ref, nextTick } from 'vue';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useRoute } from 'vue-router';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { useAccount } from 'dashboard/composables/useAccount';
import { usePolicy } from 'dashboard/composables/usePolicy';

import DeleteDialog from 'dashboard/components-next/captain/pageComponents/DeleteDialog.vue';
import DocumentCard from 'dashboard/components-next/captain/assistant/DocumentCard.vue';
import BulkSelectBar from 'dashboard/components-next/captain/assistant/BulkSelectBar.vue';
import BulkDeleteDialog from 'dashboard/components-next/captain/pageComponents/BulkDeleteDialog.vue';
import Policy from 'dashboard/components/policy.vue';
import PageLayout from 'dashboard/components-next/captain/PageLayout.vue';
import CaptainPaywall from 'dashboard/components-next/captain/pageComponents/Paywall.vue';
import RelatedResponses from 'dashboard/components-next/captain/pageComponents/document/RelatedResponses.vue';
import CreateDocumentDialog from 'dashboard/components-next/captain/pageComponents/document/CreateDocumentDialog.vue';
import DocumentPageEmptyState from 'dashboard/components-next/captain/pageComponents/emptyStates/DocumentPageEmptyState.vue';
import FeatureSpotlightPopover from 'dashboard/components-next/feature-spotlight/FeatureSpotlightPopover.vue';
import LimitBanner from 'dashboard/components-next/captain/pageComponents/document/LimitBanner.vue';
import { useI18n } from 'vue-i18n';

const route = useRoute();
const store = useStore();
const { t } = useI18n();
const { checkPermissions } = usePolicy();

const { isOnChatwootCloud } = useAccount();
const uiFlags = useMapGetter('captainDocuments/getUIFlags');
const documents = useMapGetter('captainDocuments/getRecords');
const isFetching = computed(() => uiFlags.value.fetchingList);
const documentsMeta = useMapGetter('captainDocuments/getMeta');

const selectedAssistantId = computed(() => Number(route.params.assistantId));
const canManageDocuments = computed(() => checkPermissions(['administrator']));

const selectedDocument = ref(null);
const deleteDocumentDialog = ref(null);
const bulkDeleteDialog = ref(null);
const bulkSelectedIds = ref(new Set());
const hoveredCard = ref(null);

const handleDelete = () => {
  deleteDocumentDialog.value.dialogRef.open();
};

const showRelatedResponses = ref(false);
const showCreateDialog = ref(false);
const createDocumentDialog = ref(null);
const relationQuestionDialog = ref(null);

const handleShowRelatedDocument = () => {
  showRelatedResponses.value = true;
  nextTick(() => relationQuestionDialog.value.dialogRef.open());
};
const handleCreateDocument = () => {
  showCreateDialog.value = true;
  nextTick(() => createDocumentDialog.value.dialogRef.open());
};

const handleRelatedResponseClose = () => {
  showRelatedResponses.value = false;
};

const handleCreateDialogClose = () => {
  showCreateDialog.value = false;
};

const handleAction = ({ action, id }) => {
  selectedDocument.value = documents.value.find(
    captainDocument => id === captainDocument.id
  );

  nextTick(() => {
    if (action === 'delete') {
      handleDelete();
    } else if (action === 'viewRelatedQuestions') {
      handleShowRelatedDocument();
    }
  });
};

const fetchDocuments = (page = 1) => {
  const filterParams = { page };

  if (selectedAssistantId.value) {
    filterParams.assistantId = selectedAssistantId.value;
  }
  store.dispatch('captainDocuments/get', filterParams);
};

const onPageChange = page => {
  const hadSelection = bulkSelectedIds.value.size > 0;
  fetchDocuments(page);

  if (hadSelection) {
    bulkSelectedIds.value = new Set();
  }
};

const onDeleteSuccess = () => {
  if (documents.value?.length === 0 && documentsMeta.value?.page > 1) {
    onPageChange(documentsMeta.value.page - 1);
  }
};

const buildSelectedCountLabel = computed(() => {
  const count = documents.value?.length || 0;
  const isAllSelected = bulkSelectedIds.value.size === count && count > 0;
  return isAllSelected
    ? t('CAPTAIN.DOCUMENTS.UNSELECT_ALL', { count })
    : t('CAPTAIN.DOCUMENTS.SELECT_ALL', { count });
});

const selectedCountLabel = computed(() => {
  return t('CAPTAIN.DOCUMENTS.SELECTED', {
    count: bulkSelectedIds.value.size,
  });
});

const hasBulkSelection = computed(() => bulkSelectedIds.value.size > 0);

const shouldShowSelectionControl = docId => {
  return (
    canManageDocuments.value &&
    (hoveredCard.value === docId || hasBulkSelection.value)
  );
};

const handleCardHover = (isHovered, id) => {
  hoveredCard.value = isHovered ? id : null;
};

const handleCardSelect = id => {
  if (!canManageDocuments.value) return;
  const selected = new Set(bulkSelectedIds.value);
  selected[selected.has(id) ? 'delete' : 'add'](id);
  bulkSelectedIds.value = selected;
};

const fetchDocumentsAfterBulkAction = () => {
  const hasNoDocumentsLeft = documents.value?.length === 0;
  const currentPage = documentsMeta.value?.page;

  if (hasNoDocumentsLeft) {
    const pageToFetch = currentPage > 1 ? currentPage - 1 : currentPage;
    fetchDocuments(pageToFetch);
  } else {
    fetchDocuments(currentPage);
  }

  bulkSelectedIds.value = new Set();
};

const onBulkDeleteSuccess = () => {
  fetchDocumentsAfterBulkAction();
};

onMounted(() => {
  fetchDocuments();
});
</script>

<template>
  <div class="pat-page-wrap">
    <div class="pat-page-main">
      <PageLayout
        :header-title="$t('CAPTAIN.DOCUMENTS.HEADER')"
        :button-label="$t('CAPTAIN.DOCUMENTS.ADD_NEW')"
        :button-policy="['administrator']"
        :total-count="documentsMeta.totalCount"
        :current-page="documentsMeta.page"
        :show-pagination-footer="!isFetching && !!documents.length"
        :is-fetching="isFetching"
        :is-empty="!documents.length"
        :show-know-more="false"
        :feature-flag="FEATURE_FLAGS.CAPTAIN"
        @update:current-page="onPageChange"
        @click="handleCreateDocument"
      >
        <template #subHeader>
          <Policy :permissions="['administrator']">
            <BulkSelectBar
              v-model="bulkSelectedIds"
              :all-items="documents"
              :select-all-label="buildSelectedCountLabel"
              :selected-count-label="selectedCountLabel"
              :delete-label="$t('CAPTAIN.DOCUMENTS.BULK_DELETE_BUTTON')"
              class="w-fit"
              :class="{ 'mb-2': bulkSelectedIds.size > 0 }"
              @bulk-delete="bulkDeleteDialog.dialogRef.open()"
            />
          </Policy>
        </template>

        <template #knowMore>
          <FeatureSpotlightPopover
            :button-label="$t('CAPTAIN.HEADER_KNOW_MORE')"
            :title="$t('CAPTAIN.DOCUMENTS.EMPTY_STATE.FEATURE_SPOTLIGHT.TITLE')"
            :note="$t('CAPTAIN.DOCUMENTS.EMPTY_STATE.FEATURE_SPOTLIGHT.NOTE')"
            :hide-actions="!isOnChatwootCloud"
            fallback-thumbnail="/assets/images/dashboard/captain/document-popover-light.svg"
            fallback-thumbnail-dark="/assets/images/dashboard/captain/document-popover-dark.svg"
            learn-more-url="https://chwt.app/captain-document"
          />
        </template>

        <template #emptyState>
          <DocumentPageEmptyState @click="handleCreateDocument" />
        </template>

        <template #paywall>
          <CaptainPaywall />
        </template>

        <template #body>
          <LimitBanner class="mb-5" />

          <div class="flex flex-col gap-4">
            <DocumentCard
              v-for="doc in documents"
              :id="doc.id"
              :key="doc.id"
              :name="doc.name || doc.external_link"
              :external-link="doc.external_link"
              :assistant="doc.assistant"
              :created-at="doc.created_at"
              :is-selected="canManageDocuments && bulkSelectedIds.has(doc.id)"
              :selectable="canManageDocuments"
              :show-selection-control="shouldShowSelectionControl(doc.id)"
              :show-menu="!bulkSelectedIds.has(doc.id)"
              @action="handleAction"
              @select="handleCardSelect"
              @hover="isHovered => handleCardHover(isHovered, doc.id)"
            />
          </div>
        </template>

        <RelatedResponses
          v-if="showRelatedResponses"
          ref="relationQuestionDialog"
          :captain-document="selectedDocument"
          @close="handleRelatedResponseClose"
        />
        <CreateDocumentDialog
          v-if="showCreateDialog"
          ref="createDocumentDialog"
          :assistant-id="selectedAssistantId"
          @close="handleCreateDialogClose"
        />
        <DeleteDialog
          v-if="selectedDocument"
          ref="deleteDocumentDialog"
          :entity="selectedDocument"
          type="Documents"
          @delete-success="onDeleteSuccess"
        />
        <BulkDeleteDialog
          v-if="bulkSelectedIds"
          ref="bulkDeleteDialog"
          :bulk-ids="bulkSelectedIds"
          type="AssistantDocument"
          @delete-success="onBulkDeleteSuccess"
        />
      </PageLayout>
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
