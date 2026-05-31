<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { getInboxIconByType } from 'dashboard/helper/inbox';
import {
  ROUND_ROBIN,
  EARLIEST_CREATED,
} from 'dashboard/routes/dashboard/settings/assignmentPolicy/constants';

import Breadcrumb from 'dashboard/components-next/breadcrumb/Breadcrumb.vue';
import SettingsLayout from 'dashboard/routes/dashboard/settings/SettingsLayout.vue';
import AssignmentPolicyForm from 'dashboard/routes/dashboard/settings/assignmentPolicy/pages/components/AgentAssignmentPolicyForm.vue';
import ConfirmInboxDialog from 'dashboard/routes/dashboard/settings/assignmentPolicy/pages/components/ConfirmInboxDialog.vue';
import InboxLinkDialog from 'dashboard/routes/dashboard/settings/assignmentPolicy/pages/components/InboxLinkDialog.vue';

const BASE_KEY = 'ASSIGNMENT_POLICY.AGENT_ASSIGNMENT_POLICY';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useStore();

const uiFlags = useMapGetter('assignmentPolicies/getUIFlags');
const inboxes = useMapGetter('inboxes/getAllInboxes');
const inboxUiFlags = useMapGetter('assignmentPolicies/getInboxUiFlags');
const selectedPolicyById = useMapGetter(
  'assignmentPolicies/getAssignmentPolicyById'
);

const routeId = computed(() => route.params.id);
const selectedPolicy = computed(() => selectedPolicyById.value(routeId.value));

const confirmInboxDialogRef = ref(null);
// Store the policy linked to the inbox when adding a new inbox
const inboxLinkedPolicy = ref(null);

// Inbox linking prompt from create flow
const inboxIdFromQuery = computed(() => {
  const id = route.query.inboxId;
  return id ? Number(id) : null;
});

const suggestedInbox = computed(() => {
  if (!inboxIdFromQuery.value || !inboxes.value) return null;
  return inboxes.value.find(inbox => inbox.id === inboxIdFromQuery.value);
});

const isLinkingInbox = ref(false);

const dismissInboxLinkPrompt = () => {
  router.replace({
    name: route.name,
    params: route.params,
    query: {},
  });
};

const breadcrumbItems = computed(() => {
  if (inboxIdFromQuery.value) {
    return [
      {
        label: t('INBOX_MGMT.SETTINGS'),
        routeName: 'settings_inbox_show',
        params: { inboxId: inboxIdFromQuery.value },
      },
      { label: t(`${BASE_KEY}.EDIT.HEADER.TITLE`) },
    ];
  }
  return [
    {
      label: t(`${BASE_KEY}.INDEX.HEADER.TITLE`),
      routeName: 'agent_assignment_policy_index',
    },
    { label: t(`${BASE_KEY}.EDIT.HEADER.TITLE`) },
  ];
});

const buildInboxList = allInboxes =>
  allInboxes?.map(({ name, id, email, phoneNumber, channelType, medium }) => ({
    name,
    id,
    email,
    phoneNumber,
    icon: getInboxIconByType(channelType, medium, 'line'),
  })) || [];

const policyInboxes = computed(() =>
  buildInboxList(selectedPolicy.value?.inboxes)
);

const inboxList = computed(() =>
  buildInboxList(
    inboxes.value?.slice().sort((a, b) => a.name.localeCompare(b.name))
  )
);

const formData = computed(() => ({
  name: selectedPolicy.value?.name || '',
  description: selectedPolicy.value?.description || '',
  enabled: true,
  assignmentOrder: selectedPolicy.value?.assignmentOrder || ROUND_ROBIN,
  conversationPriority:
    selectedPolicy.value?.conversationPriority || EARLIEST_CREATED,
  fairDistributionLimit: selectedPolicy.value?.fairDistributionLimit || 100,
  fairDistributionWindow: selectedPolicy.value?.fairDistributionWindow || 3600,
}));

const handleDeleteInbox = async inboxId => {
  try {
    await store.dispatch('assignmentPolicies/removeInboxPolicy', {
      policyId: selectedPolicy.value?.id,
      inboxId,
    });
    useAlert(t(`${BASE_KEY}.EDIT.INBOX_API.REMOVE.SUCCESS_MESSAGE`));
  } catch {
    useAlert(t(`${BASE_KEY}.EDIT.INBOX_API.REMOVE.ERROR_MESSAGE`));
  }
};

const handleBreadcrumbClick = ({ routeName, params }) => {
  if (params) {
    const accountId = route.params.accountId;
    const inboxId = params.inboxId;
    // Navigate using explicit path to ensure tab parameter is included
    router.push(
      `/app/accounts/${accountId}/settings/inboxes/${inboxId}/collaborators`
    );
  } else {
    router.push({ name: routeName });
  }
};

const handleNavigateToInbox = inbox => {
  router.push({
    name: 'settings_inbox_show',
    params: {
      accountId: route.params.accountId,
      inboxId: inbox.id,
    },
  });
};

const setInboxPolicy = async (inboxId, policyId) => {
  try {
    await store.dispatch('assignmentPolicies/setInboxPolicy', {
      inboxId,
      policyId,
    });
    useAlert(t(`${BASE_KEY}.FORM.INBOXES.API.SUCCESS_MESSAGE`));
    await store.dispatch(
      'assignmentPolicies/getInboxes',
      Number(routeId.value)
    );
    return true;
  } catch (error) {
    useAlert(t(`${BASE_KEY}.FORM.INBOXES.API.ERROR_MESSAGE`));
    return false;
  }
};

const handleAddInbox = async inbox => {
  try {
    const policy = await store.dispatch('assignmentPolicies/getInboxPolicy', {
      inboxId: inbox?.id,
    });

    if (policy?.id !== selectedPolicy.value?.id) {
      inboxLinkedPolicy.value = {
        ...policy,
        assignedInboxCount: policy.assignedInboxCount - 1,
      };
      confirmInboxDialogRef.value.openDialog(inbox);
      return;
    }
  } catch (error) {
    // If getInboxPolicy fails, continue to setInboxPolicy
  }

  await setInboxPolicy(inbox?.id, selectedPolicy.value?.id);
};

const handleLinkSuggestedInbox = async () => {
  if (!suggestedInbox.value) return;

  isLinkingInbox.value = true;
  const inbox = {
    id: suggestedInbox.value.id,
    name: suggestedInbox.value.name,
  };

  await handleAddInbox(inbox);

  // Clear the query param after linking
  router.replace({
    name: route.name,
    params: route.params,
    query: {},
  });
  isLinkingInbox.value = false;
};

const handleConfirmAddInbox = async inboxId => {
  const success = await setInboxPolicy(inboxId, selectedPolicy.value?.id);

  if (success) {
    // Update the policy to reflect the assigned inbox count change
    await store.dispatch('assignmentPolicies/updateInboxPolicy', {
      policy: inboxLinkedPolicy.value,
    });
    // Fetch the updated inboxes for the policy after update, to reflect real-time changes
    store.dispatch(
      'assignmentPolicies/getInboxes',
      inboxLinkedPolicy.value?.id
    );
    inboxLinkedPolicy.value = null;
    confirmInboxDialogRef.value.closeDialog();
  }
};

const handleSubmit = async formState => {
  try {
    await store.dispatch('assignmentPolicies/update', {
      id: selectedPolicy.value?.id,
      ...formState,
    });
    useAlert(t(`${BASE_KEY}.EDIT.API.SUCCESS_MESSAGE`));
  } catch {
    useAlert(t(`${BASE_KEY}.EDIT.API.ERROR_MESSAGE`));
  }
};

const fetchPolicyData = async () => {
  if (!routeId.value) return;

  // Fetch inboxes if not already loaded (needed for inbox link prompt)
  if (!inboxes.value?.length) {
    store.dispatch('inboxes/get');
  }

  // Fetch policy if not available
  if (!selectedPolicy.value?.id)
    await store.dispatch('assignmentPolicies/show', routeId.value);

  await store.dispatch('assignmentPolicies/getInboxes', Number(routeId.value));
};

watch(routeId, fetchPolicyData, { immediate: true });
</script>

<template>
  <div class="pat-page-wrap">
    <div class="pat-page-main">
      <SettingsLayout
        :is-loading="uiFlags.isFetchingItem"
        class="w-full max-w-2xl ltr:mr-auto rtl:ml-auto"
      >
        <template #header>
          <div
            class="flex items-center gap-2 w-full justify-between mb-4 min-h-10"
          >
            <Breadcrumb
              :items="breadcrumbItems"
              @click="handleBreadcrumbClick"
            />
          </div>
        </template>

        <template #body>
          <AssignmentPolicyForm
            :key="routeId"
            mode="EDIT"
            :initial-data="formData"
            :policy-inboxes="policyInboxes"
            :inbox-list="inboxList"
            show-inbox-section
            :is-loading="uiFlags.isUpdating"
            :is-inbox-loading="inboxUiFlags.isFetching"
            @submit="handleSubmit"
            @add-inbox="handleAddInbox"
            @delete-inbox="handleDeleteInbox"
            @navigate-to-inbox="handleNavigateToInbox"
          />
        </template>

        <ConfirmInboxDialog
          ref="confirmInboxDialogRef"
          @add="handleConfirmAddInbox"
        />

        <InboxLinkDialog
          :inbox="suggestedInbox"
          :is-linking="isLinkingInbox"
          @link="handleLinkSuggestedInbox"
          @dismiss="dismissInboxLinkPrompt"
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
