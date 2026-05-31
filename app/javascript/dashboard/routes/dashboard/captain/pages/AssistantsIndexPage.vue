<script setup>
import { computed, nextTick, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useRoute, useRouter } from 'vue-router';
import { useUISettings } from 'dashboard/composables/useUISettings';

import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const store = useStore();
const router = useRouter();
const { uiSettings } = useUISettings();
const route = useRoute();

const assistants = computed(
  () => store.getters['captainAssistants/getRecords']
);

const isAssistantPresent = assistantId => {
  return !!assistants.value.find(a => a.id === Number(assistantId));
};

const routeToView = (name, params) => {
  router.replace({ name, params, replace: true });
};

const generateRouterParams = () => {
  const { last_active_assistant_id: lastActiveAssistantId } =
    uiSettings.value || {};

  if (isAssistantPresent(lastActiveAssistantId)) {
    return {
      assistantId: lastActiveAssistantId,
    };
  }

  if (assistants.value.length > 0) {
    const { id: assistantId } = assistants.value[0];
    return { assistantId };
  }

  return null;
};

const routeToLastActiveAssistant = () => {
  const params = generateRouterParams();

  // No assistants found, redirect to create page
  if (!params) {
    return routeToView('captain_assistants_create_index', {
      accountId: route.params.accountId,
    });
  }

  const { navigationPath } = route.params;
  const isAValidRoute = [
    'captain_assistants_responses_index', // Faq page
    'captain_assistants_documents_index', // Document page
    'captain_assistants_scenarios_index', // Scenario page
    'captain_assistants_playground_index', // Playground page
    'captain_assistants_inboxes_index', // Inboxes page
    'captain_tools_index', // Tools page
    'captain_assistants_settings_index', // Settings page
  ].includes(navigationPath);

  const navigateTo = isAValidRoute
    ? navigationPath
    : 'captain_assistants_responses_index';

  return routeToView(navigateTo, {
    accountId: route.params.accountId,
    ...params,
  });
};

const performRouting = async () => {
  await store.dispatch('captainAssistants/get');
  nextTick(() => routeToLastActiveAssistant());
};

onMounted(() => performRouting());
</script>

<template>
  <div class="pat-page-wrap">
    <div class="pat-page-main">
      <div
        class="flex items-center justify-center w-full bg-n-surface-1 text-n-slate-11"
      >
        <Spinner />
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
