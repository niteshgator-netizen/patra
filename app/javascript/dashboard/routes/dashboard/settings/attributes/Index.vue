<script setup>
import { computed, onMounted, ref } from 'vue';
import { useToggle } from '@vueuse/core';
import { useAlert } from 'dashboard/composables';
import { picoSearch } from '@scmmishra/pico-search';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import AddAttribute from './AddAttribute.vue';
import EditAttribute from './EditAttribute.vue';
import SettingsLayout from '../SettingsLayout.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import AttributeListItem from 'dashboard/components-next/ConversationWorkflow/AttributeListItem.vue';
import { useI18n } from 'vue-i18n';
import {
  useStoreGetters,
  useStore,
  useMapGetter,
} from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';

const { t } = useI18n();

const getters = useStoreGetters();
const store = useStore();
const { currentAccount } = useAccount();
const inboxes = useMapGetter('inboxes/getInboxes');

const [showAddPopup, toggleAddPopup] = useToggle(false);
const selectedTabIndex = ref(0);
const searchQuery = ref('');
const uiFlags = computed(() => getters['attributes/getUIFlags'].value);
const [showEditPopup, toggleEditPopup] = useToggle(false);
const [showDeletePopup, toggleDeletePopup] = useToggle(false);
const selectedAttribute = ref({});
const attributeModels = ['conversation_attribute', 'contact_attribute'];

const openAddPopup = () => {
  toggleAddPopup(true);
};
const hideAddPopup = () => {
  toggleAddPopup(false);
};
const hideEditPopup = () => {
  toggleEditPopup(false);
  selectedAttribute.value = {};
};
const closeDelete = () => {
  toggleDeletePopup(false);
  selectedAttribute.value = {};
};

const tabs = computed(() => {
  return [
    {
      key: 0,
      name: t('ATTRIBUTES_MGMT.TABS.CONVERSATION'),
    },
    {
      key: 1,
      name: t('ATTRIBUTES_MGMT.TABS.CONTACT'),
    },
  ];
});

const tabsForTabBar = computed(() =>
  tabs.value.map(tab => ({ label: tab.name, key: tab.key }))
);

onMounted(() => {
  store.dispatch('attributes/get');
});

const attributeModel = computed(
  () => attributeModels[selectedTabIndex.value] || 'conversation_attribute'
);

const attributes = computed(() =>
  getters['attributes/getAttributesByModel'].value(attributeModel.value)
);

const onClickTabChange = tab => {
  selectedTabIndex.value = tab.key;
  searchQuery.value = '';
};

const handleEditAttribute = attribute => {
  selectedAttribute.value = attribute;
  toggleEditPopup(true);
};

const handleDeleteAttribute = attribute => {
  selectedAttribute.value = attribute;
  toggleDeletePopup(true);
};

const confirmDeleteAttribute = async () => {
  try {
    await store.dispatch('attributes/delete', selectedAttribute.value.id);
    useAlert(t('ATTRIBUTES_MGMT.DELETE.API.SUCCESS_MESSAGE'));
    closeDelete();
  } catch (error) {
    const errorMessage =
      error?.response?.message || t('ATTRIBUTES_MGMT.DELETE.API.ERROR_MESSAGE');
    useAlert(errorMessage);
  }
};

const requiredAttributeKeys = computed(
  () => currentAccount.value?.settings?.conversation_required_attributes || []
);

const hasPreChatBadge = attribute => {
  return (inboxes.value || []).some(inbox => {
    const fields =
      inbox?.pre_chat_form_options?.pre_chat_fields ||
      inbox?.channel?.pre_chat_form_options?.pre_chat_fields ||
      [];
    return fields.some(field => field.name === attribute.attribute_key);
  });
};

const buildBadges = attribute => {
  const badges = [];
  if (hasPreChatBadge(attribute)) {
    badges.push({
      type: 'pre-chat',
    });
  }

  if (
    attribute.attribute_model === 'conversation_attribute' &&
    requiredAttributeKeys.value.includes(attribute.attribute_key)
  ) {
    badges.push({
      type: 'resolution',
    });
  }

  return badges;
};

const derivedAttributes = computed(() =>
  attributes.value.map(attribute => ({
    ...attribute,
    label: attribute.attribute_display_name,
    type: attribute.attribute_display_type,
    value: attribute.attribute_key,
    badges: buildBadges(attribute),
  }))
);

const filteredAttributes = computed(() => {
  const query = searchQuery.value.trim();
  if (!query) return derivedAttributes.value;
  return picoSearch(derivedAttributes.value, query, [
    'attribute_display_name',
    'attribute_key',
    'attribute_description',
  ]);
});
</script>

<template>
  <div class="pat-page-wrap">
    <div class="pat-page-main">
      <SettingsLayout
        :is-loading="uiFlags.isFetching"
        :loading-message="$t('ATTRIBUTES_MGMT.LOADING')"
      >
        <template #header>
          <BaseSettingsHeader
            v-model:search-query="searchQuery"
            :title="$t('ATTRIBUTES_MGMT.HEADER')"
            :description="$t('ATTRIBUTES_MGMT.DESCRIPTION')"
            :link-text="$t('ATTRIBUTES_MGMT.LEARN_MORE')"
            :search-placeholder="$t('ATTRIBUTES_MGMT.SEARCH_PLACEHOLDER')"
            feature-name="custom_attributes"
          >
            <template v-if="attributes?.length" #count>
              <span class="text-body-main text-n-slate-11 truncate min-w-0">
                {{ $t('ATTRIBUTES_MGMT.COUNT', { n: attributes.length }) }}
              </span>
            </template>
            <template #tabs>
              <TabBar
                :tabs="tabsForTabBar"
                :initial-active-tab="selectedTabIndex"
                @tab-changed="onClickTabChange"
              />
            </template>
            <template #actions>
              <Button
                :label="$t('ATTRIBUTES_MGMT.HEADER_BTN_TXT')"
                size="sm"
                @click="openAddPopup"
              />
            </template>
          </BaseSettingsHeader>
        </template>
        <template #body>
          <div class="flex flex-col gap-4">
            <span
              v-if="!filteredAttributes.length && searchQuery"
              class="flex-1 flex items-center justify-center py-20 text-center text-body-main !text-base text-n-slate-11"
            >
              {{ $t('ATTRIBUTES_MGMT.NO_RESULTS') }}
            </span>
            <div
              v-else-if="filteredAttributes.length"
              class="flex flex-col divide-y divide-n-weak border-t border-n-weak"
            >
              <AttributeListItem
                v-for="attribute in filteredAttributes"
                :key="attribute.id"
                :attribute="attribute"
                :badges="attribute.badges"
                @edit="handleEditAttribute"
                @delete="handleDeleteAttribute"
              />
            </div>
            <p
              v-else
              class="flex-1 py-20 text-n-slate-12 flex items-center justify-center text-base"
            >
              {{ $t('ATTRIBUTES_MGMT.LIST.EMPTY_RESULT.404') }}
            </p>
          </div>
        </template>
        <AddAttribute
          v-if="showAddPopup"
          v-model:show="showAddPopup"
          :on-close="hideAddPopup"
          :selected-attribute-model-tab="selectedTabIndex"
        />
        <woot-modal v-model:show="showEditPopup" :on-close="hideEditPopup">
          <EditAttribute
            :selected-attribute="selectedAttribute"
            :is-updating="uiFlags.isUpdating"
            @on-close="hideEditPopup"
          />
        </woot-modal>
        <woot-confirm-delete-modal
          v-if="showDeletePopup"
          v-model:show="showDeletePopup"
          :title="
            $t('ATTRIBUTES_MGMT.DELETE.CONFIRM.TITLE', {
              attributeName: selectedAttribute.attribute_display_name,
            })
          "
          :message="$t('ATTRIBUTES_MGMT.DELETE.CONFIRM.MESSAGE')"
          :confirm-text="`${$t('ATTRIBUTES_MGMT.DELETE.CONFIRM.YES')} ${
            selectedAttribute.attribute_display_name || ''
          }`"
          :reject-text="$t('ATTRIBUTES_MGMT.DELETE.CONFIRM.NO')"
          :confirm-value="selectedAttribute.attribute_display_name"
          :confirm-place-holder-text="
            $t('ATTRIBUTES_MGMT.DELETE.CONFIRM.PLACE_HOLDER', {
              attributeName: selectedAttribute.attribute_display_name,
            })
          "
          @on-confirm="confirmDeleteAttribute"
          @on-close="closeDelete"
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
