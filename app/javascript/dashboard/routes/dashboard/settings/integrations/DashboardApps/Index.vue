<script>
import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { picoSearch } from '@scmmishra/pico-search';
import { BaseTable } from 'dashboard/components-next/table';
import DashboardAppModal from './DashboardAppModal.vue';
import DashboardAppsRow from './DashboardAppsRow.vue';
import BaseSettingsHeader from '../../components/BaseSettingsHeader.vue';
import SettingsLayout from '../../SettingsLayout.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

export default {
  components: {
    BaseSettingsHeader,
    SettingsLayout,
    BaseTable,
    DashboardAppModal,
    DashboardAppsRow,
    NextButton,
  },
  data() {
    return {
      loading: {},
      showDashboardAppPopup: false,
      showDeleteConfirmationPopup: false,
      selectedApp: {},
      mode: 'CREATE',
      searchQuery: '',
    };
  },
  computed: {
    ...mapGetters({
      records: 'dashboardApps/getRecords',
      uiFlags: 'dashboardApps/getUIFlags',
    }),
    filteredRecords() {
      const query = this.searchQuery.trim();
      if (!query) return this.records;
      return picoSearch(this.records, query, ['title']);
    },
    tableHeaders() {
      return [
        this.$t('INTEGRATION_SETTINGS.DASHBOARD_APPS.LIST.TABLE_HEADER.NAME'),
        this.$t(
          'INTEGRATION_SETTINGS.DASHBOARD_APPS.LIST.TABLE_HEADER.ENDPOINT'
        ),
        this.$t(
          'INTEGRATION_SETTINGS.DASHBOARD_APPS.LIST.TABLE_HEADER.ACTIONS'
        ),
      ];
    },
  },
  mounted() {
    this.$store.dispatch('dashboardApps/get');
  },
  methods: {
    toggleDashboardAppPopup() {
      this.showDashboardAppPopup = !this.showDashboardAppPopup;
      this.selectedApp = {};
    },
    openDeletePopup(response) {
      this.showDeleteConfirmationPopup = true;
      this.selectedApp = response;
    },
    openCreatePopup() {
      this.mode = 'CREATE';
      this.selectedApp = {};
      this.showDashboardAppPopup = true;
    },
    closeDeletePopup() {
      this.showDeleteConfirmationPopup = false;
    },
    editApp(app) {
      this.loading[app.id] = true;
      this.mode = 'UPDATE';
      this.selectedApp = app;
      this.showDashboardAppPopup = true;
    },
    confirmDeletion() {
      this.loading[this.selectedApp.id] = true;
      this.closeDeletePopup();
      this.deleteApp(this.selectedApp.id);
    },
    async deleteApp(id) {
      try {
        await this.$store.dispatch('dashboardApps/delete', id);
        useAlert(
          this.$t('INTEGRATION_SETTINGS.DASHBOARD_APPS.DELETE.API_SUCCESS')
        );
      } catch (error) {
        useAlert(
          this.$t('INTEGRATION_SETTINGS.DASHBOARD_APPS.DELETE.API_ERROR')
        );
      }
    },
  },
};
</script>

<template>
  <div class="pat-page-wrap">
    <div class="pat-page-main">
      <SettingsLayout
        :is-loading="uiFlags.isFetching"
        :loading-message="
          $t('INTEGRATION_SETTINGS.DASHBOARD_APPS.LIST.LOADING')
        "
        :no-records-found="!records.length"
        :no-records-message="$t('INTEGRATION_SETTINGS.DASHBOARD_APPS.LIST.404')"
      >
        <template #header>
          <BaseSettingsHeader
            v-model:search-query="searchQuery"
            :title="$t('INTEGRATION_SETTINGS.DASHBOARD_APPS.TITLE')"
            :description="$t('INTEGRATION_SETTINGS.DASHBOARD_APPS.DESCRIPTION')"
            :link-text="$t('INTEGRATION_SETTINGS.DASHBOARD_APPS.LEARN_MORE')"
            :search-placeholder="
              $t('INTEGRATION_SETTINGS.DASHBOARD_APPS.SEARCH_PLACEHOLDER')
            "
            feature-name="dashboard_apps"
            :back-button-label="$t('INTEGRATION_SETTINGS.HEADER')"
          >
            <template v-if="records?.length" #count>
              <span class="text-body-main text-n-slate-11">
                {{
                  $t('INTEGRATION_SETTINGS.DASHBOARD_APPS.COUNT', {
                    n: records.length,
                  })
                }}
              </span>
            </template>
            <template #actions>
              <NextButton
                :label="
                  $t('INTEGRATION_SETTINGS.DASHBOARD_APPS.HEADER_BTN_TXT')
                "
                size="sm"
                @click="openCreatePopup"
              />
            </template>
          </BaseSettingsHeader>
        </template>
        <template #body>
          <span
            v-if="!filteredRecords.length && searchQuery"
            class="flex-1 flex items-center justify-center py-20 text-center text-body-main !text-base text-n-slate-11"
          >
            {{ $t('INTEGRATION_SETTINGS.DASHBOARD_APPS.NO_RESULTS') }}
          </span>
          <BaseTable v-else :headers="tableHeaders" :items="filteredRecords">
            <template #row="{ items }">
              <DashboardAppsRow
                v-for="(dashboardAppItem, index) in items"
                :key="dashboardAppItem.id"
                :index="index"
                :app="dashboardAppItem"
                @edit="editApp"
                @delete="openDeletePopup"
              />
            </template>
          </BaseTable>
        </template>
        <DashboardAppModal
          v-if="showDashboardAppPopup"
          :show="showDashboardAppPopup"
          :mode="mode"
          :selected-app-data="selectedApp"
          @close="toggleDashboardAppPopup"
        />

        <woot-delete-modal
          v-model:show="showDeleteConfirmationPopup"
          :on-close="closeDeletePopup"
          :on-confirm="confirmDeletion"
          :title="$t('INTEGRATION_SETTINGS.DASHBOARD_APPS.DELETE.TITLE')"
          :message="
            $t('INTEGRATION_SETTINGS.DASHBOARD_APPS.DELETE.MESSAGE', {
              appName: selectedApp.title,
            })
          "
          :confirm-text="
            $t('INTEGRATION_SETTINGS.DASHBOARD_APPS.DELETE.CONFIRM_YES')
          "
          :reject-text="
            $t('INTEGRATION_SETTINGS.DASHBOARD_APPS.DELETE.CONFIRM_NO')
          "
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
