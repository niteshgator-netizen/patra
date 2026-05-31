<script>
import AddSLA from './AddSLA.vue';
import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from 'dashboard/routes/dashboard/settings/components/BaseSettingsHeader.vue';
import SLAPaywallEnterprise from './SLAPaywallEnterprise.vue';
import {
  BaseTable,
  BaseTableRow,
  BaseTableCell,
} from 'dashboard/components-next/table';
import WootLabel from 'dashboard/components-next/label/Label.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

import { mapGetters } from 'vuex';
import { convertSecondsToTimeUnit } from '@chatwoot/utils';
import { useAlert } from 'dashboard/composables';
import { picoSearch } from '@scmmishra/pico-search';

export default {
  components: {
    AddSLA,
    SettingsLayout,
    BaseSettingsHeader,
    SLAPaywallEnterprise,
    BaseTable,
    BaseTableRow,
    BaseTableCell,
    WootLabel,
    Icon,
    NextButton,
  },
  data() {
    return {
      loading: {},
      showAddPopup: false,
      showDeleteConfirmationPopup: false,
      selectedResponse: {},
      searchQuery: '',
    };
  },
  computed: {
    ...mapGetters({
      isOnChatwootCloud: 'globalConfig/isOnChatwootCloud',
      isFeatureEnabledonAccount: 'accounts/isFeatureEnabledonAccount',
      records: 'sla/getSLA',
      currentUser: 'getCurrentUser',
      accountId: 'getCurrentAccountId',
      uiFlags: 'sla/getUIFlags',
    }),
    deleteConfirmText() {
      return this.$t('SLA.DELETE.CONFIRM.YES');
    },
    deleteRejectText() {
      return this.$t('SLA.DELETE.CONFIRM.NO');
    },
    deleteMessage() {
      return ` ${this.selectedResponse.name}`;
    },
    isBehindAPaywall() {
      return !this.isFeatureEnabledonAccount(this.accountId, 'sla');
    },
    isSuperAdmin() {
      return this.currentUser.type === 'SuperAdmin';
    },
    tableHeaders() {
      return [
        this.$t('SLA.LIST.TABLE_HEADER.SLA'),
        this.$t('SLA.LIST.TABLE_HEADER.BUSINESS_HOURS'),
        this.$t('SLA.LIST.RESPONSE_TYPES.SHORT_HAND.FRT'),
        this.$t('SLA.LIST.RESPONSE_TYPES.SHORT_HAND.NRT'),
        this.$t('SLA.LIST.RESPONSE_TYPES.SHORT_HAND.RT'),
        this.$t('INTEGRATION_APPS.LIST.ACTIONS'),
      ];
    },
    filteredRecords() {
      const query = this.searchQuery.trim();
      if (!query) return this.records;
      return picoSearch(this.records, query, ['name', 'description']);
    },
  },
  mounted() {
    this.$store.dispatch('sla/get');
  },
  methods: {
    openAddPopup() {
      if (this.isBehindAPaywall) {
        return;
      }
      this.showAddPopup = true;
    },
    hideAddPopup() {
      this.showAddPopup = false;
    },
    openDeletePopup(response) {
      this.showDeleteConfirmationPopup = true;
      this.selectedResponse = response;
    },
    closeDeletePopup() {
      this.showDeleteConfirmationPopup = false;
    },
    confirmDeletion() {
      this.loading[this.selectedResponse.id] = true;
      this.closeDeletePopup();
      this.deleteSla(this.selectedResponse.id);
    },
    deleteSla(id) {
      this.$store
        .dispatch('sla/delete', id)
        .then(() => {
          useAlert(this.$t('SLA.DELETE.API.SUCCESS_MESSAGE'));
        })
        .catch(() => {
          useAlert(this.$t('SLA.DELETE.API.ERROR_MESSAGE'));
        })
        .finally(() => {
          this.loading[this.selectedResponse.id] = false;
        });
    },
    displayTime(threshold) {
      const { time, unit } = convertSecondsToTimeUnit(threshold, {
        minute: 'm',
        hour: 'h',
        day: 'd',
      });
      if (!time) return '-';
      return `${time}${unit}`;
    },
    onClickCTA() {
      this.$router.push({
        name: 'billing_settings_index',
        params: { accountId: this.accountId },
      });
    },
  },
};
</script>

<template>
  <div class="pat-page-wrap">
    <div class="pat-page-main">
      <SettingsLayout
        :is-loading="uiFlags.isFetching"
        :loading-message="$t('SLA.LOADING')"
      >
        <template #header>
          <BaseSettingsHeader
            v-model:search-query="searchQuery"
            :title="$t('SLA.HEADER')"
            :description="$t('SLA.DESCRIPTION')"
            :link-text="$t('SLA.LEARN_MORE')"
            :search-placeholder="
              isBehindAPaywall ? '' : $t('SLA.SEARCH_PLACEHOLDER')
            "
            feature-name="sla"
          >
            <template v-if="!isBehindAPaywall && records?.length" #count>
              <span class="text-body-main text-n-slate-11">
                {{ $t('SLA.COUNT', { n: records.length }) }}
              </span>
            </template>
            <template v-if="!isBehindAPaywall" #actions>
              <NextButton
                :label="$t('SLA.ADD_ACTION')"
                size="sm"
                @click="openAddPopup"
              />
            </template>
          </BaseSettingsHeader>
        </template>
        <template #body>
          <SLAPaywallEnterprise
            v-if="isBehindAPaywall"
            :is-super-admin="isSuperAdmin"
            :is-on-chatwoot-cloud="isOnChatwootCloud"
            @upgrade="onClickCTA"
          />
          <BaseTable
            v-else
            :headers="tableHeaders"
            :items="filteredRecords"
            :no-data-message="
              !records.length
                ? $t('SLA.LIST.404')
                : searchQuery && !filteredRecords.length
                  ? $t('SLA.SEARCH.NO_RESULTS')
                  : ''
            "
          >
            <template #header-2>
              <div class="flex items-center gap-1">
                <span class="text-heading-3">
                  {{ $t('SLA.LIST.RESPONSE_TYPES.SHORT_HAND.FRT') }}
                </span>
                <Icon
                  v-tooltip.left="$t('SLA.LIST.RESPONSE_TYPES.FRT')"
                  icon="i-lucide-info"
                  class="size-3.5 text-n-slate-10 cursor-help"
                />
              </div>
            </template>
            <template #header-3>
              <div class="flex items-center gap-1">
                <span class="text-heading-3">
                  {{ $t('SLA.LIST.RESPONSE_TYPES.SHORT_HAND.NRT') }}
                </span>
                <Icon
                  v-tooltip.left="$t('SLA.LIST.RESPONSE_TYPES.NRT')"
                  icon="i-lucide-info"
                  class="size-3.5 text-n-slate-10 cursor-help"
                />
              </div>
            </template>
            <template #header-4>
              <div class="flex items-center gap-1">
                <span class="text-heading-3">
                  {{ $t('SLA.LIST.RESPONSE_TYPES.SHORT_HAND.RT') }}
                </span>
                <Icon
                  v-tooltip.left="$t('SLA.LIST.RESPONSE_TYPES.RT')"
                  icon="i-lucide-info"
                  class="size-3.5 text-n-slate-10 cursor-help"
                />
              </div>
            </template>
            <template #row="{ items }">
              <BaseTableRow v-for="sla in items" :key="sla.id" :item="sla">
                <template #default>
                  <BaseTableCell>
                    <div class="flex flex-col gap-1 min-w-0">
                      <span class="text-body-main text-n-slate-12 truncate">
                        {{ sla.name }}
                      </span>
                      <span class="text-body-main text-n-slate-11 line-clamp-1">
                        {{ sla.description }}
                      </span>
                    </div>
                  </BaseTableCell>

                  <BaseTableCell class="w-40">
                    <WootLabel
                      :label="
                        sla.only_during_business_hours
                          ? $t('SLA.LIST.BUSINESS_HOURS_ON')
                          : $t('SLA.LIST.BUSINESS_HOURS_OFF')
                      "
                      :color="sla.only_during_business_hours ? 'teal' : 'slate'"
                      compact
                    >
                      <template #icon>
                        <Icon
                          :icon="
                            sla.only_during_business_hours
                              ? 'i-lucide-alarm-clock-check'
                              : 'i-lucide-alarm-clock-off'
                          "
                          class="size-3.5"
                          :class="
                            sla.only_during_business_hours
                              ? 'text-n-teal-11'
                              : 'text-n-slate-11'
                          "
                        />
                      </template>
                    </WootLabel>
                  </BaseTableCell>

                  <BaseTableCell align="start" class="w-24">
                    <span class="text-body-main text-n-slate-12">
                      {{ displayTime(sla.first_response_time_threshold) }}
                    </span>
                  </BaseTableCell>

                  <BaseTableCell align="start" class="w-24">
                    <span class="text-body-main text-n-slate-12">
                      {{ displayTime(sla.next_response_time_threshold) }}
                    </span>
                  </BaseTableCell>

                  <BaseTableCell align="start" class="w-24">
                    <span class="text-body-main text-n-slate-12">
                      {{ displayTime(sla.resolution_time_threshold) }}
                    </span>
                  </BaseTableCell>

                  <BaseTableCell align="end" class="w-12">
                    <div class="flex justify-end">
                      <NextButton
                        v-tooltip.top="$t('SLA.FORM.DELETE')"
                        icon="i-woot-bin"
                        slate
                        sm
                        class="hover:enabled:text-n-ruby-11 hover:enabled:bg-n-ruby-2"
                        :is-loading="loading[sla.id]"
                        @click="openDeletePopup(sla)"
                      />
                    </div>
                  </BaseTableCell>
                </template>
              </BaseTableRow>
            </template>
          </BaseTable>

          <woot-modal v-model:show="showAddPopup" :on-close="hideAddPopup">
            <AddSLA @close="hideAddPopup" />
          </woot-modal>

          <woot-delete-modal
            v-model:show="showDeleteConfirmationPopup"
            :on-close="closeDeletePopup"
            :on-confirm="confirmDeletion"
            :title="$t('SLA.DELETE.CONFIRM.TITLE')"
            :message="$t('SLA.DELETE.CONFIRM.MESSAGE')"
            :message-value="deleteMessage"
            :confirm-text="deleteConfirmText"
            :reject-text="deleteRejectText"
          />
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
