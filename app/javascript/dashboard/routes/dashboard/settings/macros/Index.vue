<script setup>
import { useAlert } from 'dashboard/composables';
import { picoSearch } from '@scmmishra/pico-search';
import MacrosTableRow from './MacrosTableRow.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import SettingsLayout from '../SettingsLayout.vue';
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStoreGetters, useStore } from 'dashboard/composables/store';
import Button from 'dashboard/components-next/button/Button.vue';
import { BaseTable } from 'dashboard/components-next/table';
import { useAdmin } from 'dashboard/composables/useAdmin';

const getters = useStoreGetters();
const store = useStore();
const { t } = useI18n();
const { isAdmin } = useAdmin();

const showDeleteConfirmationPopup = ref(false);
const selectedMacro = ref({});
const searchQuery = ref('');

const records = computed(() => getters['macros/getMacros'].value);
const uiFlags = computed(() => getters['macros/getUIFlags'].value);

const filteredRecords = computed(() => {
  const query = searchQuery.value.trim();
  if (!query) return records.value;
  return picoSearch(records.value, query, ['name']);
});

const deleteMessage = computed(() => ` ${selectedMacro.value.name}?`);

onMounted(() => {
  store.dispatch('macros/get');
});

const deleteMacro = async id => {
  try {
    await store.dispatch('macros/delete', id);
    useAlert(t('MACROS.DELETE.API.SUCCESS_MESSAGE'));
  } catch (error) {
    useAlert(t('MACROS.DELETE.API.ERROR_MESSAGE'));
  }
};

const openDeletePopup = response => {
  showDeleteConfirmationPopup.value = true;
  selectedMacro.value = response;
};

const closeDeletePopup = () => {
  showDeleteConfirmationPopup.value = false;
};

const confirmDeletion = () => {
  closeDeletePopup();
  deleteMacro(selectedMacro.value.id);
};

const tableHeaders = computed(() => {
  return [
    t('MACROS.LIST.TABLE_HEADER.NAME'),
    t('MACROS.LIST.TABLE_HEADER.CREATED BY'),
    t('MACROS.LIST.TABLE_HEADER.LAST_UPDATED_BY'),
    t('MACROS.LIST.TABLE_HEADER.VISIBILITY'),
    t('MACROS.LIST.TABLE_HEADER.ACTIONS'),
  ];
});
</script>

<template>
  <div class="pat-page-wrap">
    <div class="pat-page-main">
      <SettingsLayout
        :no-records-message="$t('MACROS.LIST.404')"
        :no-records-found="!records.length"
        :is-loading="uiFlags.isFetching"
        :loading-message="$t('MACROS.LOADING')"
        feature-name="macros"
      >
        <template #header>
          <BaseSettingsHeader
            v-model:search-query="searchQuery"
            :title="$t('MACROS.HEADER')"
            :description="$t('MACROS.DESCRIPTION')"
            :link-text="$t('MACROS.LEARN_MORE')"
            :search-placeholder="$t('MACROS.SEARCH_PLACEHOLDER')"
            feature-name="macros"
          >
            <template v-if="records?.length" #count>
              <span class="text-body-main text-n-slate-11">
                {{ $t('MACROS.COUNT', { n: records.length }) }}
              </span>
            </template>
            <template #actions>
              <router-link :to="{ name: 'macros_new' }">
                <Button :label="$t('MACROS.HEADER_BTN_TXT')" size="sm" />
              </router-link>
            </template>
          </BaseSettingsHeader>
        </template>
        <template #body>
          <BaseTable
            :headers="tableHeaders"
            :items="filteredRecords"
            :no-data-message="
              searchQuery ? $t('MACROS.NO_RESULTS') : $t('MACROS.LIST.404')
            "
          >
            <template #row="{ items }">
              <MacrosTableRow
                v-for="macro in items"
                :key="macro.id"
                :macro="macro"
                :can-manage-public-macros="isAdmin"
                @delete="openDeletePopup(macro)"
              />
            </template>
          </BaseTable>
          <woot-delete-modal
            v-model:show="showDeleteConfirmationPopup"
            :on-close="closeDeletePopup"
            :on-confirm="confirmDeletion"
            :title="$t('LABEL_MGMT.DELETE.CONFIRM.TITLE')"
            :message="$t('MACROS.DELETE.CONFIRM.MESSAGE')"
            :message-value="deleteMessage"
            :confirm-text="$t('MACROS.DELETE.CONFIRM.YES')"
            :reject-text="$t('MACROS.DELETE.CONFIRM.NO')"
          />
        </template>
      </SettingsLayout>
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
