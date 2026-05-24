<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import AutomationFlowsAPI from 'dashboard/api/automationFlows';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const { t } = useI18n();

const loading = ref(true);
const flows = ref([]);
const error = ref(null);

const activeCount = computed(() => flows.value.filter(f => f.active).length);

const loadFlows = async () => {
  loading.value = true;
  try {
    const { data } = await AutomationFlowsAPI.get();
    flows.value = data;
  } catch (e) {
    error.value = e.message;
  } finally {
    loading.value = false;
  }
};

const toggleActive = async flow => {
  await AutomationFlowsAPI.update(flow.id, { active: !flow.active });
  await loadFlows();
};

const duplicateFlow = async id => {
  await AutomationFlowsAPI.duplicate(id);
  await loadFlows();
};

const deleteFlow = async id => {
  await AutomationFlowsAPI.delete(id);
  await loadFlows();
};

const createFromTemplate = async key => {
  await AutomationFlowsAPI.fromTemplate(key);
  await loadFlows();
};

onMounted(loadFlows);
</script>

<template>
  <div class="flex flex-col gap-6 p-6">
    <header class="flex items-center justify-between">
      <div>
        <h1 class="text-2xl font-semibold text-n-slate-12">
          {{ $t('PATRA.FLOWS.TITLE') }}
        </h1>
        <p class="text-sm text-n-slate-11">
          {{ $t('PATRA.FLOWS.SUBTITLE') }}
        </p>
      </div>
      <div class="flex gap-2">
        <button
          class="px-3 py-2 text-sm rounded-lg bg-n-brand text-white"
          @click="createFromTemplate('welcome_new_customer')"
        >
          {{ $t('PATRA.FLOWS.FROM_TEMPLATE') }}
        </button>
      </div>
    </header>

    <div v-if="loading" class="flex justify-center py-12">
      <Spinner />
    </div>
    <p v-else-if="error" class="text-n-ruby-11">{{ error }}</p>

    <div v-else class="grid gap-3">
      <div class="text-sm text-n-slate-11">
        {{ activeCount }} / {{ flows.length }} {{ $t('PATRA.FLOWS.ACTIVE') }}
      </div>
      <div
        v-for="flow in flows"
        :key="flow.id"
        class="flex items-center justify-between p-4 border rounded-xl border-n-weak bg-n-solid-1"
      >
        <div>
          <h3 class="font-medium text-n-slate-12">{{ flow.name }}</h3>
          <p class="text-xs text-n-slate-11">
            {{ flow.trigger_type }} · {{ flow.stats?.runs || 0 }} runs ·
            {{ flow.completion_rate || 0 }}% completion
          </p>
        </div>
        <div class="flex items-center gap-2">
          <button
            class="px-2 py-1 text-xs rounded-lg border border-n-weak"
            @click="toggleActive(flow)"
          >
            {{ flow.active ? $t('PATRA.FLOWS.DEACTIVATE') : $t('PATRA.FLOWS.ACTIVATE') }}
          </button>
          <button
            class="px-2 py-1 text-xs rounded-lg border border-n-weak"
            @click="duplicateFlow(flow.id)"
          >
            {{ $t('PATRA.FLOWS.DUPLICATE') }}
          </button>
          <button
            class="px-2 py-1 text-xs rounded-lg text-n-ruby-11 border border-n-weak"
            @click="deleteFlow(flow.id)"
          >
            {{ $t('PATRA.FLOWS.DELETE') }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
