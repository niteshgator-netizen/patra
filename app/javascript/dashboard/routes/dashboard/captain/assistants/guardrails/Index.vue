<script setup>
import { computed, ref } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { picoSearch } from '@scmmishra/pico-search';
import { useStore } from 'dashboard/composables/store';
import { useMapGetter } from 'dashboard/composables/store';
import { useUISettings } from 'dashboard/composables/useUISettings';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';

import PageLayout from 'dashboard/components-next/captain/PageLayout.vue';
import SettingsHeader from 'dashboard/components-next/captain/pageComponents/settings/SettingsHeader.vue';
import SuggestedRules from 'dashboard/components-next/captain/assistant/SuggestedRules.vue';
import AddNewRulesInput from 'dashboard/components-next/captain/assistant/AddNewRulesInput.vue';
import AddNewRulesDialog from 'dashboard/components-next/captain/assistant/AddNewRulesDialog.vue';
import RuleCard from 'dashboard/components-next/captain/assistant/RuleCard.vue';
import BulkSelectBar from 'dashboard/components-next/captain/assistant/BulkSelectBar.vue';

const { t } = useI18n();
const route = useRoute();
const store = useStore();
const { uiSettings, updateUISettings } = useUISettings();

const uiFlags = useMapGetter('captainAssistants/getUIFlags');
const assistantId = computed(() => Number(route.params.assistantId));
const isFetching = computed(() => uiFlags.value.fetchingItem);
const assistant = computed(() =>
  store.getters['captainAssistants/getRecord'](assistantId.value)
);

const searchQuery = ref('');
const newInlineRule = ref('');
const newDialogRule = ref('');

const guardrailsContent = computed(() => assistant.value?.guardrails || []);

const backUrl = computed(() => ({
  name: 'captain_assistants_settings_index',
  params: {
    accountId: route.params.accountId,
    assistantId: assistantId.value,
  },
}));

const displayGuardrails = computed(() =>
  guardrailsContent.value.map((c, idx) => ({ id: idx, content: c }))
);

const guardrailsExample = [
  {
    id: 1,
    content:
      'Block queries that share or request sensitive personal information (e.g. phone numbers, passwords).',
  },
  {
    id: 2,
    content:
      'Reject queries that include offensive, discriminatory, or threatening language.',
  },
  {
    id: 3,
    content:
      'Deflect when the assistant is asked for legal or medical diagnosis or treatment.',
  },
];

const filteredGuardrails = computed(() => {
  const query = searchQuery.value.trim();
  if (!query) return displayGuardrails.value;
  return picoSearch(displayGuardrails.value, query, ['content']);
});

const shouldShowSuggestedRules = computed(() => {
  return uiSettings.value?.show_guardrails_suggestions !== false;
});

const closeSuggestedRules = () => {
  updateUISettings({ show_guardrails_suggestions: false });
};

// Bulk selection & hover state
const bulkSelectedIds = ref(new Set());
const hoveredCard = ref(null);

const handleRuleSelect = id => {
  const selected = new Set(bulkSelectedIds.value);
  selected[selected.has(id) ? 'delete' : 'add'](id);
  bulkSelectedIds.value = selected;
};

const handleRuleHover = (isHovered, id) => {
  hoveredCard.value = isHovered ? id : null;
};

const buildSelectedCountLabel = computed(() => {
  const count = displayGuardrails.value.length || 0;
  const isAllSelected = bulkSelectedIds.value.size === count && count > 0;
  return isAllSelected
    ? t('CAPTAIN.ASSISTANTS.GUARDRAILS.BULK_ACTION.UNSELECT_ALL', { count })
    : t('CAPTAIN.ASSISTANTS.GUARDRAILS.BULK_ACTION.SELECT_ALL', { count });
});

const selectedCountLabel = computed(() => {
  return t('CAPTAIN.ASSISTANTS.GUARDRAILS.BULK_ACTION.SELECTED', {
    count: bulkSelectedIds.value.size,
  });
});

const saveGuardrails = async list => {
  await store.dispatch('captainAssistants/update', {
    id: assistantId.value,
    assistant: { guardrails: list },
  });
};

const addGuardrail = async content => {
  try {
    const newGuardrails = [...guardrailsContent.value, content];
    await saveGuardrails(newGuardrails);
    useAlert(t('CAPTAIN.ASSISTANTS.GUARDRAILS.API.ADD.SUCCESS'));
  } catch (error) {
    useAlert(t('CAPTAIN.ASSISTANTS.GUARDRAILS.API.ADD.ERROR'));
  }
};

const editGuardrail = async ({ id, content }) => {
  try {
    const updated = [...guardrailsContent.value];
    updated[id] = content;
    await saveGuardrails(updated);
    useAlert(t('CAPTAIN.ASSISTANTS.GUARDRAILS.API.UPDATE.SUCCESS'));
  } catch {
    useAlert(t('CAPTAIN.ASSISTANTS.GUARDRAILS.API.UPDATE.ERROR'));
  }
};

const deleteGuardrail = async id => {
  try {
    const updated = guardrailsContent.value.filter((_, idx) => idx !== id);
    await saveGuardrails(updated);
    useAlert(t('CAPTAIN.ASSISTANTS.GUARDRAILS.API.DELETE.SUCCESS'));
  } catch {
    useAlert(t('CAPTAIN.ASSISTANTS.GUARDRAILS.API.DELETE.ERROR'));
  }
};

const bulkDeleteGuardrails = async () => {
  try {
    if (bulkSelectedIds.value.size === 0) return;
    const updated = guardrailsContent.value.filter(
      (_, idx) => !bulkSelectedIds.value.has(idx)
    );
    await saveGuardrails(updated);
    bulkSelectedIds.value.clear();
    useAlert(t('CAPTAIN.ASSISTANTS.GUARDRAILS.API.DELETE.SUCCESS'));
  } catch {
    useAlert(t('CAPTAIN.ASSISTANTS.GUARDRAILS.API.DELETE.ERROR'));
  }
};

const addAllExample = () => {
  updateUISettings({ show_guardrails_suggestions: false });
  try {
    const exampleContents = guardrailsExample.map(example => example.content);
    const newGuardrails = [...guardrailsContent.value, ...exampleContents];
    saveGuardrails(newGuardrails);
  } catch {
    useAlert(t('CAPTAIN.ASSISTANTS.GUARDRAILS.API.ADD.ERROR'));
  }
};
</script>

<template>
  <div class="pat-page-wrap">
    <div class="pat-page-main">
      <PageLayout
        :header-title="$t('CAPTAIN.ASSISTANTS.GUARDRAILS.TITLE')"
        :is-fetching="isFetching"
        :back-url="backUrl"
        :show-know-more="false"
        :show-pagination-footer="false"
        :show-assistant-switcher="false"
      >
        <template #body>
          <SettingsHeader
            :heading="$t('CAPTAIN.ASSISTANTS.GUARDRAILS.TITLE')"
            :description="$t('CAPTAIN.ASSISTANTS.GUARDRAILS.DESCRIPTION')"
          />
          <div v-if="shouldShowSuggestedRules" class="flex mt-7 flex-col gap-4">
            <SuggestedRules
              :title="$t('CAPTAIN.ASSISTANTS.GUARDRAILS.ADD.SUGGESTED.TITLE')"
              :items="guardrailsExample"
              @add="addAllExample"
              @close="closeSuggestedRules"
            >
              <template #default="{ item }">
                <div class="flex items-center justify-between w-full">
                  <span class="text-sm text-n-slate-12">
                    {{ item.content }}
                  </span>
                  <Button
                    :label="
                      $t(
                        'CAPTAIN.ASSISTANTS.GUARDRAILS.ADD.SUGGESTED.ADD_SINGLE'
                      )
                    "
                    ghost
                    xs
                    slate
                    class="!text-sm !text-n-slate-11 flex-shrink-0"
                    @click="addGuardrail(item.content)"
                  />
                </div>
              </template>
            </SuggestedRules>
          </div>
          <div class="flex mt-7 flex-col gap-4">
            <div class="flex justify-between items-center">
              <BulkSelectBar
                v-model="bulkSelectedIds"
                :all-items="displayGuardrails"
                :select-all-label="buildSelectedCountLabel"
                :selected-count-label="selectedCountLabel"
                :delete-label="
                  $t(
                    'CAPTAIN.ASSISTANTS.GUARDRAILS.BULK_ACTION.BULK_DELETE_BUTTON'
                  )
                "
                @bulk-delete="bulkDeleteGuardrails"
              >
                <template #default-actions>
                  <AddNewRulesDialog
                    v-model="newDialogRule"
                    :placeholder="
                      t('CAPTAIN.ASSISTANTS.GUARDRAILS.ADD.NEW.PLACEHOLDER')
                    "
                    :button-label="
                      t('CAPTAIN.ASSISTANTS.GUARDRAILS.ADD.NEW.TITLE')
                    "
                    :confirm-label="
                      t('CAPTAIN.ASSISTANTS.GUARDRAILS.ADD.NEW.CREATE')
                    "
                    :cancel-label="
                      t('CAPTAIN.ASSISTANTS.GUARDRAILS.ADD.NEW.CANCEL')
                    "
                    @add="addGuardrail"
                  />
                  <!-- Will enable this feature in future -->
                  <!-- <div class="h-4 w-px bg-n-strong" />
              <Button
                :label="t('CAPTAIN.ASSISTANTS.GUARDRAILS.ADD.NEW.TEST_ALL')"
                xs
                ghost
                slate
                class="!text-sm"
              /> -->
                </template>
              </BulkSelectBar>
              <div
                v-if="displayGuardrails.length && bulkSelectedIds.size === 0"
                class="max-w-[22.5rem] w-full min-w-0"
              >
                <Input
                  v-model="searchQuery"
                  :placeholder="
                    t('CAPTAIN.ASSISTANTS.GUARDRAILS.LIST.SEARCH_PLACEHOLDER')
                  "
                />
              </div>
            </div>
            <div v-if="displayGuardrails.length === 0" class="mt-1 mb-2">
              <span class="text-n-slate-11 text-sm">
                {{ t('CAPTAIN.ASSISTANTS.GUARDRAILS.EMPTY_MESSAGE') }}
              </span>
            </div>
            <div v-else-if="filteredGuardrails.length === 0" class="mt-1 mb-2">
              <span class="text-n-slate-11 text-sm">
                {{ t('CAPTAIN.ASSISTANTS.GUARDRAILS.SEARCH_EMPTY_MESSAGE') }}
              </span>
            </div>
            <div v-else class="flex flex-col gap-2">
              <RuleCard
                v-for="guardrail in filteredGuardrails"
                :id="guardrail.id"
                :key="guardrail.id"
                :content="guardrail.content"
                :is-selected="bulkSelectedIds.has(guardrail.id)"
                :selectable="
                  hoveredCard === guardrail.id || bulkSelectedIds.size > 0
                "
                @select="handleRuleSelect"
                @edit="editGuardrail"
                @delete="deleteGuardrail"
                @hover="isHovered => handleRuleHover(isHovered, guardrail.id)"
              />
            </div>
            <AddNewRulesInput
              v-model="newInlineRule"
              :placeholder="
                t('CAPTAIN.ASSISTANTS.GUARDRAILS.ADD.SUGGESTED.PLACEHOLDER')
              "
              :label="t('CAPTAIN.ASSISTANTS.GUARDRAILS.ADD.SUGGESTED.SAVE')"
              @add="addGuardrail"
            />
          </div>
        </template>
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
