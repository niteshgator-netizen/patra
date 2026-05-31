<script setup>
import { ref, computed, onMounted } from 'vue';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import { picoSearch } from '@scmmishra/pico-search';

import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import AgentBotModal from './components/AgentBotModal.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import {
  BaseTable,
  BaseTableRow,
  BaseTableCell,
} from 'dashboard/components-next/table';

const MODAL_TYPES = {
  CREATE: 'create',
  EDIT: 'edit',
};

const store = useStore();
const { t } = useI18n();

const agentBots = useMapGetter('agentBots/getBots');
const uiFlags = useMapGetter('agentBots/getUIFlags');

const selectedBot = ref({});
const searchQuery = ref('');
const loading = ref({});
const modalType = ref(MODAL_TYPES.CREATE);
const agentBotModalRef = ref(null);
const agentBotDeleteDialogRef = ref(null);

const tableHeaders = computed(() => {
  return [
    t('AGENT_BOTS.LIST.TABLE_HEADER.DETAILS'),
    t('AGENT_BOTS.LIST.TABLE_HEADER.URL'),
    t('AGENT_BOTS.LIST.TABLE_HEADER.ACTIONS'),
  ];
});

const selectedBotName = computed(() => selectedBot.value?.name || '');

const filteredAgentBots = computed(() => {
  const query = searchQuery.value.trim();
  if (!query) return agentBots.value;
  return picoSearch(agentBots.value, query, ['name', 'description']);
});

const openAddModal = () => {
  modalType.value = MODAL_TYPES.CREATE;
  selectedBot.value = {};
  agentBotModalRef.value.dialogRef.open();
};

const openEditModal = bot => {
  modalType.value = MODAL_TYPES.EDIT;
  selectedBot.value = bot;
  agentBotModalRef.value.dialogRef.open();
};

const openDeletePopup = bot => {
  selectedBot.value = bot;
  agentBotDeleteDialogRef.value.open();
};

const deleteAgentBot = async id => {
  try {
    await store.dispatch('agentBots/delete', id);
    useAlert(t('AGENT_BOTS.DELETE.API.SUCCESS_MESSAGE'));
  } catch (error) {
    useAlert(t('AGENT_BOTS.DELETE.API.ERROR_MESSAGE'));
  } finally {
    loading.value[id] = false;
    selectedBot.value = {};
  }
};

const confirmDeletion = () => {
  loading.value[selectedBot.value.id] = true;
  deleteAgentBot(selectedBot.value.id);
  agentBotDeleteDialogRef.value.close();
};

onMounted(() => {
  store.dispatch('agentBots/get');
});
</script>

<template>
  <div class="pat-page-wrap">
    <div class="pat-page-main">
      <SettingsLayout
        :is-loading="uiFlags.isFetching"
        :loading-message="t('AGENT_BOTS.LIST.LOADING')"
        :no-records-found="!agentBots.length"
        :no-records-message="t('AGENT_BOTS.LIST.404')"
      >
        <template #header>
          <BaseSettingsHeader
            v-model:search-query="searchQuery"
            :title="t('AGENT_BOTS.HEADER')"
            :description="t('AGENT_BOTS.DESCRIPTION')"
            :link-text="t('AGENT_BOTS.LEARN_MORE')"
            :search-placeholder="t('AGENT_BOTS.SEARCH_PLACEHOLDER')"
            feature-name="agent_bots"
          >
            <template v-if="agentBots?.length" #count>
              <span class="text-body-main text-n-slate-11">
                {{ $t('AGENT_BOTS.COUNT', { n: agentBots.length }) }}
              </span>
            </template>
            <template #actions>
              <Button
                :label="$t('AGENT_BOTS.ADD.TITLE')"
                size="sm"
                @click="openAddModal"
              />
            </template>
          </BaseSettingsHeader>
        </template>
        <template #body>
          <BaseTable
            :headers="tableHeaders"
            :items="filteredAgentBots"
            :no-data-message="
              searchQuery
                ? t('AGENT_BOTS.NO_RESULTS')
                : t('AGENT_BOTS.LIST.404')
            "
          >
            <template #row="{ items }">
              <BaseTableRow v-for="bot in items" :key="bot.id" :item="bot">
                <template #default>
                  <BaseTableCell class="max-w-0">
                    <div class="flex items-center gap-4 min-w-0">
                      <Avatar
                        :name="bot.name"
                        :src="bot.thumbnail"
                        :size="40"
                        class="flex-shrink-0"
                      />
                      <div class="min-w-0">
                        <div class="flex items-center gap-2">
                          <span class="text-body-main text-n-slate-12 truncate">
                            {{ bot.name }}
                          </span>
                          <span
                            v-if="bot.system_bot"
                            class="text-xs text-n-slate-12 bg-n-blue-5 rounded-md py-0.5 px-1 flex-shrink-0"
                          >
                            {{ $t('AGENT_BOTS.GLOBAL_BOT_BADGE') }}
                          </span>
                        </div>
                        <span
                          class="text-body-main text-n-slate-11 block truncate"
                        >
                          {{ bot.description }}
                        </span>
                      </div>
                    </div>
                  </BaseTableCell>

                  <BaseTableCell class="max-w-0">
                    <span class="text-body-main text-n-slate-11 truncate block">
                      {{ bot.outgoing_url || bot.bot_config?.webhook_url }}
                    </span>
                  </BaseTableCell>

                  <BaseTableCell align="end" class="w-24">
                    <div class="flex gap-3 justify-end flex-shrink-0">
                      <Button
                        v-if="!bot.system_bot"
                        v-tooltip.top="t('AGENT_BOTS.EDIT.BUTTON_TEXT')"
                        icon="i-woot-edit-pen"
                        slate
                        sm
                        :is-loading="loading[bot.id]"
                        @click="openEditModal(bot)"
                      />
                      <Button
                        v-if="!bot.system_bot"
                        v-tooltip.top="t('AGENT_BOTS.DELETE.BUTTON_TEXT')"
                        icon="i-woot-bin"
                        slate
                        sm
                        class="hover:enabled:text-n-ruby-11 hover:enabled:bg-n-ruby-2"
                        :is-loading="loading[bot.id]"
                        @click="openDeletePopup(bot)"
                      />
                    </div>
                  </BaseTableCell>
                </template>
              </BaseTableRow>
            </template>
          </BaseTable>
        </template>

        <AgentBotModal
          ref="agentBotModalRef"
          :type="modalType"
          :selected-bot="selectedBot"
        />

        <Dialog
          ref="agentBotDeleteDialogRef"
          type="alert"
          :title="t('AGENT_BOTS.DELETE.CONFIRM.TITLE')"
          :description="
            t('AGENT_BOTS.DELETE.CONFIRM.MESSAGE', { name: selectedBotName })
          "
          :is-loading="uiFlags.isDeleting"
          :confirm-button-label="t('AGENT_BOTS.DELETE.CONFIRM.YES')"
          :cancel-button-label="t('AGENT_BOTS.DELETE.CONFIRM.NO')"
          @confirm="confirmDeletion"
        />
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
