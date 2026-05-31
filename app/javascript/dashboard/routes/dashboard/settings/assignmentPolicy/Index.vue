<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter, useRoute } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import SettingsLayout from '../SettingsLayout.vue';
import AssignmentCard from 'dashboard/components-next/AssignmentPolicy/AssignmentCard/AssignmentCard.vue';

const router = useRouter();
const route = useRoute();
const { t } = useI18n();

const accountId = computed(() => Number(route.params.accountId));
const isFeatureEnabledonAccount = useMapGetter(
  'accounts/isFeatureEnabledonAccount'
);

const agentAssignments = computed(() => {
  const assignments = [
    {
      key: 'agent_assignment_policy_index',
      title: t('ASSIGNMENT_POLICY.INDEX.ASSIGNMENT_POLICY.TITLE'),
      description: t('ASSIGNMENT_POLICY.INDEX.ASSIGNMENT_POLICY.DESCRIPTION'),
      features: [
        {
          icon: 'i-lucide-circle-fading-arrow-up',
          label: t('ASSIGNMENT_POLICY.INDEX.ASSIGNMENT_POLICY.FEATURES.0'),
        },
        {
          icon: 'i-lucide-scale',
          label: t('ASSIGNMENT_POLICY.INDEX.ASSIGNMENT_POLICY.FEATURES.1'),
        },
        {
          icon: 'i-lucide-inbox',
          label: t('ASSIGNMENT_POLICY.INDEX.ASSIGNMENT_POLICY.FEATURES.2'),
        },
      ],
    },
  ];

  // Only show Agent Capacity if BOTH assignment_v2 AND advanced_assignment are enabled
  // advanced_assignment identifies premium users
  const hasAssignmentV2 = isFeatureEnabledonAccount.value(
    accountId.value,
    'assignment_v2'
  );
  const hasAdvancedAssignment = isFeatureEnabledonAccount.value(
    accountId.value,
    'advanced_assignment'
  );

  if (hasAssignmentV2 && hasAdvancedAssignment) {
    assignments.push({
      key: 'agent_capacity_policy_index',
      title: t('ASSIGNMENT_POLICY.INDEX.AGENT_CAPACITY_POLICY.TITLE'),
      description: t(
        'ASSIGNMENT_POLICY.INDEX.AGENT_CAPACITY_POLICY.DESCRIPTION'
      ),
      features: [
        {
          icon: 'i-lucide-glass-water',
          label: t('ASSIGNMENT_POLICY.INDEX.AGENT_CAPACITY_POLICY.FEATURES.0'),
        },
        {
          icon: 'i-lucide-circle-minus',
          label: t('ASSIGNMENT_POLICY.INDEX.AGENT_CAPACITY_POLICY.FEATURES.1'),
        },
        {
          icon: 'i-lucide-users-round',
          label: t('ASSIGNMENT_POLICY.INDEX.AGENT_CAPACITY_POLICY.FEATURES.2'),
        },
      ],
    });
  }

  return assignments;
});

const handleClick = key => {
  router.push({ name: key });
};
</script>

<template>
  <div class="pat-page-wrap">
    <div class="pat-page-main">
      <SettingsLayout :no-records-found="false" class="gap-10">
        <template #header>
          <BaseSettingsHeader
            :title="$t('ASSIGNMENT_POLICY.INDEX.HEADER.TITLE')"
            :description="$t('ASSIGNMENT_POLICY.INDEX.HEADER.DESCRIPTION')"
            feature-name="assignment-policy"
          />
        </template>

        <template #body>
          <div class="grid grid-cols-1 2xl:grid-cols-2 gap-6 mt-4">
            <AssignmentCard
              v-for="item in agentAssignments"
              :key="item.key"
              :title="item.title"
              :description="item.description"
              :features="item.features"
              @click="handleClick(item.key)"
            />
          </div>
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
