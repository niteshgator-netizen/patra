<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';

import Policy from 'dashboard/components/policy.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import CompaniesDetailsLayout from 'dashboard/components-next/Companies/CompaniesDetailsLayout.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CompanyContactsSidebar from 'dashboard/components-next/Companies/CompanyDetail/CompanyContactsSidebar.vue';
import CompanyProfileCard from 'dashboard/components-next/Companies/CompanyDetail/CompanyProfileCard.vue';
import ConfirmCompanyDeleteDialog from 'dashboard/components-next/Companies/CompanyDetail/ConfirmCompanyDeleteDialog.vue';
import { useCompaniesStore } from 'dashboard/stores/companies';

const route = useRoute();
const router = useRouter();
const companiesStore = useCompaniesStore();
const { t } = useI18n();

const confirmDeleteDialogRef = ref(null);
const selectedCandidate = ref(null);

const companyId = computed(() => Number(route.params.companyId));
const company = computed(() => companiesStore.getRecord(companyId.value));
const companyContacts = computed(() => companiesStore.companyContacts);
const companyContactsMeta = computed(() => companiesStore.companyContactsMeta);
const contactSearchResults = computed(
  () => companiesStore.contactSearchResults
);
const uiFlags = computed(() => companiesStore.getUIFlags);

const isFetchingCompany = computed(() => uiFlags.value.fetchingItem);
const isFetchingContacts = computed(() => uiFlags.value.fetchingContacts);
const isSearchingContacts = computed(() => uiFlags.value.searchingContacts);
const isManagingContacts = computed(
  () => uiFlags.value.creatingContact || uiFlags.value.removingContact
);
const isDeletingCompany = computed(() => uiFlags.value.deletingItem);
const hasCompany = computed(() => Boolean(company.value?.id));
const showInitialLoadingState = computed(
  () =>
    !hasCompany.value && (isFetchingCompany.value || isFetchingContacts.value)
);

const breadcrumbItems = computed(() => [
  { label: t('COMPANIES.HEADER') },
  ...(hasCompany.value
    ? [{ label: company.value?.name || t('COMPANIES.UNNAMED') }]
    : []),
]);

const goToCompaniesIndex = () => {
  router.push({
    name: 'companies_dashboard_index',
    params: { accountId: route.params.accountId },
    query: { page: '1' },
  });
};

const goToCompaniesList = () => {
  if (window.history.state?.back) {
    router.back();
    return;
  }
  goToCompaniesIndex();
};

const loadCompanyContactsPage = async page => {
  if (!companyId.value) return;
  await companiesStore.getCompanyContacts(companyId.value, page);
};

const openDeleteCompanyDialog = () => {
  confirmDeleteDialogRef.value?.dialogRef.open();
};

const clearSelectedCandidate = () => {
  selectedCandidate.value = null;
};

const handleContactSearch = async query => {
  await companiesStore.searchCompanyContactCandidates({
    companyId: companyId.value,
    search: query,
  });
};

const handleConfirmContactSelection = async () => {
  const candidate = selectedCandidate.value;
  if (!candidate) return;

  const isReassigning =
    candidate.company?.id && candidate.company.id !== companyId.value;
  const message = isReassigning
    ? t('COMPANIES.DETAIL.CONTACTS.MESSAGES.REASSIGN_SUCCESS')
    : t('COMPANIES.DETAIL.CONTACTS.MESSAGES.ADD_SUCCESS');

  try {
    await companiesStore.attachContactToCompany(companyId.value, candidate.id);
    useAlert(message);
    clearSelectedCandidate();
  } catch {
    const errorMessage = isReassigning
      ? t('COMPANIES.DETAIL.CONTACTS.MESSAGES.REASSIGN_ERROR')
      : t('COMPANIES.DETAIL.CONTACTS.MESSAGES.ADD_ERROR');
    useAlert(errorMessage);
  }
};

const handleRemoveContact = async contactId => {
  const currentPage = Number(companyContactsMeta.value.page || 1);
  const nextPage =
    currentPage > 1 && companyContacts.value.length === 1
      ? currentPage - 1
      : currentPage;

  try {
    await companiesStore.removeContactFromCompany(
      companyId.value,
      contactId,
      nextPage
    );
    useAlert(t('COMPANIES.DETAIL.CONTACTS.MESSAGES.REMOVE_SUCCESS'));
  } catch {
    useAlert(t('COMPANIES.DETAIL.CONTACTS.MESSAGES.REMOVE_ERROR'));
  }
};

const handleDeleteCompany = async () => {
  try {
    await companiesStore.delete(companyId.value);
    useAlert(t('COMPANIES.DETAIL.DELETE.MESSAGES.SUCCESS'));
    confirmDeleteDialogRef.value?.dialogRef.close();
    goToCompaniesIndex();
  } catch {
    useAlert(t('COMPANIES.DETAIL.DELETE.MESSAGES.ERROR'));
  }
};

watch(
  companyId,
  async id => {
    companiesStore.resetCompanyDetailState();
    clearSelectedCandidate();
    if (!id) return;
    await Promise.allSettled([
      companiesStore.show(id),
      companiesStore.getCompanyContacts(id),
    ]);
  },
  { immediate: true }
);

onBeforeUnmount(() => {
  companiesStore.resetCompanyDetailState();
});
</script>

<template>
  <div class="pat-page-wrap">
    <div class="pat-page-main">
      <CompaniesDetailsLayout
        :breadcrumb-items="breadcrumbItems"
        @back="goToCompaniesList"
      >
        <div
          v-if="showInitialLoadingState"
          class="flex flex-col items-center justify-center gap-3 py-24 text-n-slate-11"
        >
          <Spinner />
          <span class="text-sm">{{ t('COMPANIES.DETAIL.LOADING') }}</span>
        </div>

        <div
          v-else-if="!hasCompany"
          class="flex flex-col items-center justify-center gap-3 px-6 py-24 text-center rounded-2xl border border-n-weak bg-n-solid-2"
        >
          <span class="text-lg font-medium text-n-slate-12">
            {{ t('COMPANIES.DETAIL.EMPTY_STATE.TITLE') }}
          </span>
          <p class="max-w-md text-sm text-n-slate-11">
            {{ t('COMPANIES.DETAIL.EMPTY_STATE.SUBTITLE') }}
          </p>
        </div>

        <div v-else class="flex flex-col gap-6">
          <CompanyProfileCard
            :company="company"
            :is-loading="isFetchingCompany"
          />

          <Policy :permissions="['administrator']">
            <section
              class="flex flex-col items-start w-full gap-4 pt-6 border-t border-n-strong"
            >
              <div class="flex flex-col gap-2">
                <h6 class="text-base font-medium text-n-slate-12">
                  {{ t('COMPANIES.DETAIL.DELETE.SECTION_TITLE') }}
                </h6>
                <span class="text-sm text-n-slate-11">
                  {{ t('COMPANIES.DETAIL.DELETE.SECTION_DESCRIPTION') }}
                </span>
              </div>
              <Button
                :label="t('COMPANIES.DETAIL.DELETE.BUTTON')"
                color="ruby"
                :disabled="isDeletingCompany"
                @click="openDeleteCompanyDialog"
              />
            </section>
          </Policy>
        </div>

        <template v-if="hasCompany" #sidebar>
          <CompanyContactsSidebar
            :company="company"
            :contacts="companyContacts"
            :meta="companyContactsMeta"
            :is-loading="isFetchingContacts"
            :is-busy="isManagingContacts"
            :search-results="contactSearchResults"
            :is-searching="isSearchingContacts"
            :selected-contact="selectedCandidate"
            @cancel-contact-selection="clearSelectedCandidate"
            @confirm-contact-selection="handleConfirmContactSelection"
            @search="handleContactSearch"
            @select-contact="contact => (selectedCandidate = contact)"
            @remove-contact="handleRemoveContact"
            @update:current-page="loadCompanyContactsPage"
          />
        </template>

        <ConfirmCompanyDeleteDialog
          ref="confirmDeleteDialogRef"
          :company="company"
          :is-loading="isDeletingCompany"
          @confirm="handleDeleteCompany"
        />
      </CompaniesDetailsLayout>
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
