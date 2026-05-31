<script setup>
import { computed, ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore } from 'dashboard/composables/store';
import { useMapGetter } from 'dashboard/composables/store';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { useAccount } from 'dashboard/composables/useAccount';
import Button from 'dashboard/components-next/button/Button.vue';
import PageLayout from 'dashboard/components-next/captain/PageLayout.vue';
import SettingsHeader from 'dashboard/components-next/captain/pageComponents/settings/SettingsHeader.vue';
import AssistantBasicSettingsForm from 'dashboard/components-next/captain/pageComponents/assistant/settings/AssistantBasicSettingsForm.vue';
import AssistantSystemSettingsForm from 'dashboard/components-next/captain/pageComponents/assistant/settings/AssistantSystemSettingsForm.vue';
import AssistantControlItems from 'dashboard/components-next/captain/pageComponents/assistant/settings/AssistantControlItems.vue';
import DeleteDialog from 'dashboard/components-next/captain/pageComponents/DeleteDialog.vue';

const { t } = useI18n();
const { isCloudFeatureEnabled } = useAccount();

const isCaptainV2Enabled = computed(() =>
  isCloudFeatureEnabled(FEATURE_FLAGS.CAPTAIN_V2)
);
const route = useRoute();
const router = useRouter();
const store = useStore();

const deleteAssistantDialog = ref(null);

const uiFlags = useMapGetter('captainAssistants/getUIFlags');
const assistants = useMapGetter('captainAssistants/getRecords');
const isFetching = computed(() => uiFlags.value.fetchingItem);
const assistantId = computed(() => Number(route.params.assistantId));
const assistant = computed(() =>
  store.getters['captainAssistants/getRecord'](assistantId.value)
);

const controlItems = computed(() => {
  return [
    {
      name: t(
        'CAPTAIN.ASSISTANTS.SETTINGS.CONTROL_ITEMS.OPTIONS.GUARDRAILS.TITLE'
      ),
      description: t(
        'CAPTAIN.ASSISTANTS.SETTINGS.CONTROL_ITEMS.OPTIONS.GUARDRAILS.DESCRIPTION'
      ),
      routeName: 'captain_assistants_guardrails_index',
    },
    {
      name: t(
        'CAPTAIN.ASSISTANTS.SETTINGS.CONTROL_ITEMS.OPTIONS.RESPONSE_GUIDELINES.TITLE'
      ),
      description: t(
        'CAPTAIN.ASSISTANTS.SETTINGS.CONTROL_ITEMS.OPTIONS.RESPONSE_GUIDELINES.DESCRIPTION'
      ),
      routeName: 'captain_assistants_guidelines_index',
    },
  ];
});

const handleSubmit = async updatedAssistant => {
  try {
    await store.dispatch('captainAssistants/update', {
      id: assistantId.value,
      ...updatedAssistant,
    });
    useAlert(t('CAPTAIN.ASSISTANTS.EDIT.SUCCESS_MESSAGE'));
  } catch (error) {
    const errorMessage =
      error?.message || t('CAPTAIN.ASSISTANTS.EDIT.ERROR_MESSAGE');
    useAlert(errorMessage);
  }
};

const handleDelete = () => {
  deleteAssistantDialog.value.dialogRef.open();
};

const handleDeleteSuccess = () => {
  // Get remaining assistants after deletion
  const remainingAssistants = assistants.value.filter(
    a => a.id !== assistantId.value
  );

  if (remainingAssistants.length > 0) {
    // Navigate to the first available assistant's settings
    const nextAssistant = remainingAssistants[0];
    router.push({
      name: 'captain_assistants_settings_index',
      params: {
        accountId: route.params.accountId,
        assistantId: nextAssistant.id,
      },
    });
  } else {
    // No assistants left, redirect to create assistant page
    router.push({
      name: 'captain_assistants_create_index',
      params: { accountId: route.params.accountId },
    });
  }
};
</script>

<template>
  <div class="pat-page-wrap">
    <div class="pat-page-main">
      <PageLayout
        :is-fetching="isFetching"
        :show-pagination-footer="false"
        :show-know-more="false"
        :class="{
          '[&>header>div]:max-w-[80rem] [&>main>div]:max-w-[80rem]':
            isCaptainV2Enabled,
        }"
      >
        <template #body>
          <div
            class="gap-6 lg:gap-16 pb-8"
            :class="{ 'grid grid-cols-2': isCaptainV2Enabled }"
          >
            <div class="flex flex-col gap-6">
              <div class="flex flex-col gap-6">
                <SettingsHeader
                  :heading="
                    t('CAPTAIN.ASSISTANTS.SETTINGS.BASIC_SETTINGS.TITLE')
                  "
                  :description="
                    t('CAPTAIN.ASSISTANTS.SETTINGS.BASIC_SETTINGS.DESCRIPTION')
                  "
                />
                <AssistantBasicSettingsForm
                  :assistant="assistant"
                  @submit="handleSubmit"
                />
              </div>
              <span class="h-px w-full bg-n-weak mt-2" />
              <div class="flex flex-col gap-6">
                <SettingsHeader
                  :heading="
                    t('CAPTAIN.ASSISTANTS.SETTINGS.SYSTEM_SETTINGS.TITLE')
                  "
                  :description="
                    t('CAPTAIN.ASSISTANTS.SETTINGS.SYSTEM_SETTINGS.DESCRIPTION')
                  "
                />
                <AssistantSystemSettingsForm
                  :assistant="assistant"
                  @submit="handleSubmit"
                />
              </div>
              <span class="h-px w-full bg-n-weak mt-2" />
              <div class="flex items-end justify-between w-full gap-4">
                <div class="flex flex-col gap-2">
                  <h6 class="text-n-slate-12 text-base font-medium">
                    {{ t('CAPTAIN.ASSISTANTS.SETTINGS.DELETE.TITLE') }}
                  </h6>
                  <span class="text-n-slate-11 text-sm">
                    {{ t('CAPTAIN.ASSISTANTS.SETTINGS.DELETE.DESCRIPTION') }}
                  </span>
                </div>
                <div class="flex-shrink-0">
                  <Button
                    :label="
                      t('CAPTAIN.ASSISTANTS.SETTINGS.DELETE.BUTTON_TEXT', {
                        assistantName: assistant.name,
                      })
                    "
                    color="ruby"
                    class="max-w-56 !w-fit"
                    @click="handleDelete"
                  />
                </div>
              </div>
            </div>
            <div v-if="isCaptainV2Enabled" class="flex flex-col gap-6">
              <SettingsHeader
                :heading="t('CAPTAIN.ASSISTANTS.SETTINGS.CONTROL_ITEMS.TITLE')"
                :description="
                  t('CAPTAIN.ASSISTANTS.SETTINGS.CONTROL_ITEMS.DESCRIPTION')
                "
              />
              <div class="flex flex-col gap-6">
                <AssistantControlItems
                  v-for="item in controlItems"
                  :key="item.name"
                  :control-item="item"
                />
              </div>
            </div>
          </div>
        </template>
        <DeleteDialog
          v-if="assistant"
          ref="deleteAssistantDialog"
          :entity="assistant"
          type="Assistants"
          translation-key="ASSISTANTS"
          @delete-success="handleDeleteSuccess"
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
