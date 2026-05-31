<script setup>
import { ref, computed, watch, provide } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import MacroForm from './MacroForm.vue';
import { MACRO_ACTION_TYPES } from './constants';
import { useAlert } from 'dashboard/composables';
import actionQueryGenerator from 'dashboard/helper/actionQueryGenerator.js';
import { useMacros } from 'dashboard/composables/useMacros';
import { useAdmin } from 'dashboard/composables/useAdmin';

const store = useStore();
const getters = useStoreGetters();

const route = useRoute();
const router = useRouter();

const { t } = useI18n();

const { getMacroDropdownValues } = useMacros();
const { isAdmin } = useAdmin();

const macro = ref(null);
const mode = ref('CREATE');

const macroActionTypes = computed(() => {
  return MACRO_ACTION_TYPES.map(type => ({
    ...type,
    label: t(`MACROS.ACTIONS.${type.label}`),
  }));
});

provide('macroActionTypes', macroActionTypes);

const uiFlags = computed(() => getters['macros/getUIFlags'].value);
const macroId = computed(() => route.params.macroId);
const isPublicMacroReadOnly = computed(
  () => macro.value?.visibility === 'global' && !isAdmin.value
);

const fetchDropdownData = () => {
  store.dispatch('agents/get');
  store.dispatch('teams/get');
  store.dispatch('labels/get');
};

const formatMacro = macroData => {
  const formattedActions = macroData.actions.map(action => {
    let actionParams = [];
    if (action.action_params.length) {
      const inputType = macroActionTypes.value.find(
        item => item.key === action.action_name
      ).inputType;
      if (inputType === 'multi_select' || inputType === 'search_select') {
        actionParams = getMacroDropdownValues(action.action_name).filter(item =>
          [...action.action_params].includes(item.id)
        );
      } else if (inputType === 'team_message') {
        actionParams = {
          team_ids: getMacroDropdownValues(action.action_name).filter(item =>
            [...action.action_params[0].team_ids].includes(item.id)
          ),
          message: action.action_params[0].message,
        };
      } else actionParams = [...action.action_params];
    }
    return {
      ...action,
      action_params: actionParams,
    };
  });
  return {
    ...macroData,
    actions: formattedActions,
  };
};

const manifestMacro = async () => {
  await store.dispatch('macros/getSingleMacro', macroId.value);
  const singleMacro = store.getters['macros/getMacro'](macroId.value);
  macro.value = formatMacro(singleMacro);
};

const fetchMacro = () => {
  mode.value = 'EDIT';
  manifestMacro();
};

const initNewMacro = () => {
  mode.value = 'CREATE';
  macro.value = {
    name: '',
    actions: [
      {
        action_name: 'assign_team',
        action_params: [],
      },
    ],
    visibility: isAdmin.value ? 'global' : 'personal',
  };
};

watch(
  () => route,
  () => {
    fetchDropdownData();
    if (route.params.macroId) {
      fetchMacro();
    } else {
      initNewMacro();
    }
  },
  { immediate: true, deep: true }
);

const saveMacro = async macroData => {
  if (isPublicMacroReadOnly.value) return;

  try {
    const action = mode.value === 'EDIT' ? 'macros/update' : 'macros/create';
    const successMessage =
      mode.value === 'EDIT'
        ? t('MACROS.EDIT.API.SUCCESS_MESSAGE')
        : t('MACROS.ADD.API.SUCCESS_MESSAGE');
    let serializedMacro = JSON.parse(JSON.stringify(macroData));
    serializedMacro.actions = actionQueryGenerator(serializedMacro.actions);
    await store.dispatch(action, serializedMacro);
    useAlert(successMessage);
    router.push({ name: 'macros_wrapper' });
  } catch (error) {
    useAlert(t('MACROS.ERROR'));
  }
};
</script>

<template>
  <div class="pat-page-wrap">
    <div class="pat-page-main">
      <div
        class="flex flex-col gap-6 mb-8 max-w-7xl mx-auto h-full w-full !px-6"
      >
        <woot-loading-state
          v-if="uiFlags.isFetchingItem"
          :message="t('MACROS.EDITOR.LOADING')"
        />
        <MacroForm
          v-if="macro && !uiFlags.isFetchingItem"
          :macro-data="macro"
          :can-manage-public-macros="isAdmin"
          :read-only="isPublicMacroReadOnly"
          @update:macro-data="macro = $event"
          @submit="saveMacro"
        />
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
