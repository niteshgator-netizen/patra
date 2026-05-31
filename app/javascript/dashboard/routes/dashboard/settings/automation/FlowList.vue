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
  <div class="pat-page-wrap">
    <div class="pat-page-main">
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
            {{ activeCount }} / {{ flows.length }}
            {{ $t('PATRA.FLOWS.ACTIVE') }}
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
                {{
                  flow.active
                    ? $t('PATRA.FLOWS.DEACTIVATE')
                    : $t('PATRA.FLOWS.ACTIVATE')
                }}
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
