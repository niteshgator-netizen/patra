<script setup>
import { computed, onMounted, ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import AutomationFlowsAPI from 'dashboard/api/automationFlows';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const flow = ref({ name: '', trigger_type: 'message_received', steps: [] });
const selectedStepId = ref(null);
const saving = ref(false);
const previewLog = ref([]);

const STEP_TYPES = [
  'send_message', 'wait', 'condition', 'assign_agent', 'add_tag',
  'remove_tag', 'resolve', 'notify', 'ab_split', 'goto',
];

const selectedStep = computed(() =>
  flow.value.steps?.find(s => s.id === selectedStepId.value)
);

const loadFlow = async () => {
  if (!route.params.flowId) return;
  const { data } = await AutomationFlowsAPI.show(route.params.flowId);
  flow.value = data;
};

const addStep = type => {
  const id = `step_${Date.now()}`;
  flow.value.steps.push({ id, type, config: {}, next_step_id: null });
  selectedStepId.value = id;
};

const saveFlow = async () => {
  saving.value = true;
  try {
    if (route.params.flowId) {
      await AutomationFlowsAPI.update(route.params.flowId, flow.value);
    } else {
      const { data } = await AutomationFlowsAPI.create(flow.value);
      router.replace({ name: 'patra_flow_builder', params: { flowId: data.id } });
    }
  } finally {
    saving.value = false;
  }
};

const runPreview = async () => {
  const contactId = prompt(t('PATRA.FLOWS.PREVIEW_CONTACT_ID'));
  if (!contactId) return;
  const { data } = await AutomationFlowsAPI.preview(route.params.flowId, { contact_id: contactId });
  previewLog.value = data.step_log || [];
};

onMounted(loadFlow);
</script>

<template>
  <div class="flex h-full">
    <aside class="w-48 p-4 border-r border-n-weak bg-n-solid-1">
      <h3 class="mb-3 text-xs font-semibold uppercase text-n-slate-11">
        {{ $t('PATRA.FLOWS.STEP_PALETTE') }}
      </h3>
      <button
        v-for="type in STEP_TYPES"
        :key="type"
        class="block w-full px-2 py-1 mb-1 text-xs text-left rounded-lg hover:bg-n-alpha-2"
        @click="addStep(type)"
      >
        {{ type }}
      </button>
    </aside>

    <main class="flex flex-col flex-1 p-4">
      <div class="flex items-center justify-between mb-4">
        <input
          v-model="flow.name"
          class="text-xl font-semibold bg-transparent text-n-slate-12"
          :placeholder="$t('PATRA.FLOWS.NAME_PLACEHOLDER')"
        />
        <div class="flex gap-2">
          <button
            class="px-3 py-1 text-sm rounded-lg border border-n-weak"
            @click="runPreview"
          >
            {{ $t('PATRA.FLOWS.PREVIEW') }}
          </button>
          <button
            class="px-3 py-1 text-sm text-white rounded-lg bg-n-brand"
            :disabled="saving"
            @click="saveFlow"
          >
            {{ $t('PATRA.FLOWS.SAVE') }}
          </button>
        </div>
      </div>

      <div class="flex flex-wrap gap-3 min-h-[200px] p-4 rounded-xl bg-n-alpha-1">
        <div
          v-for="step in flow.steps"
          :key="step.id"
          class="p-3 cursor-pointer rounded-lg border border-n-weak bg-n-solid-1 min-w-[140px]"
          :class="{ 'ring-2 ring-n-brand': selectedStepId === step.id }"
          @click="selectedStepId = step.id"
        >
          <p class="text-xs font-medium uppercase text-n-brand">{{ step.type }}</p>
          <p class="mt-1 text-xs truncate text-n-slate-11">
            {{ step.config?.message || step.config?.tag || step.config?.duration_minutes || '—' }}
          </p>
        </div>
      </div>

      <div v-if="previewLog.length" class="p-3 mt-4 text-xs rounded-lg bg-n-alpha-1">
        <h4 class="mb-2 font-medium">{{ $t('PATRA.FLOWS.PREVIEW_LOG') }}</h4>
        <pre class="whitespace-pre-wrap">{{ JSON.stringify(previewLog, null, 2) }}</pre>
      </div>
    </main>

    <aside v-if="selectedStep" class="w-64 p-4 border-l border-n-weak">
      <h3 class="mb-3 text-sm font-medium">{{ selectedStep.type }}</h3>
      <textarea
        v-if="selectedStep.type === 'send_message'"
        v-model="selectedStep.config.message"
        class="w-full p-2 text-sm rounded-lg border border-n-weak"
        rows="4"
        :placeholder="$t('PATRA.FLOWS.MESSAGE_PLACEHOLDER')"
      />
      <input
        v-if="selectedStep.type === 'wait'"
        v-model.number="selectedStep.config.duration_minutes"
        type="number"
        class="w-full p-2 text-sm rounded-lg border border-n-weak"
        :placeholder="$t('PATRA.FLOWS.WAIT_MINUTES')"
      />
      <input
        v-if="selectedStep.type === 'add_tag' || selectedStep.type === 'remove_tag'"
        v-model="selectedStep.config.tag"
        class="w-full p-2 text-sm rounded-lg border border-n-weak"
        :placeholder="$t('PATRA.FLOWS.TAG_PLACEHOLDER')"
      />
    </aside>
  </div>
</template>
