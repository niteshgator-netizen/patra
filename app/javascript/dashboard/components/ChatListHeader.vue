<script setup>
import { computed } from 'vue';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { formatNumber } from '@chatwoot/utils';
import wootConstants from 'dashboard/constants/globals';

import ConversationBasicFilter from './widgets/conversation/ConversationBasicFilter.vue';
import SwitchLayout from 'dashboard/routes/dashboard/conversation/search/SwitchLayout.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import ComposeConversation from 'dashboard/components-next/NewConversation/ComposeConversation.vue';

const props = defineProps({
  pageTitle: { type: String, required: true },
  hasAppliedFilters: { type: Boolean, required: true },
  hasActiveFolders: { type: Boolean, required: true },
  activeStatus: { type: String, required: true },
  isOnExpandedLayout: { type: Boolean, required: true },
  conversationStats: { type: Object, required: true },
  isListLoading: { type: Boolean, required: true },
});

const emit = defineEmits([
  'addFolders',
  'deleteFolders',
  'resetFilters',
  'basicFilterChange',
  'filtersModal',
]);

const { uiSettings, updateUISettings } = useUISettings();

const onBasicFilterChange = (value, type) => {
  emit('basicFilterChange', value, type);
};

const hasAppliedFiltersOrActiveFolders = computed(() => {
  return props.hasAppliedFilters || props.hasActiveFolders;
});

const allCount = computed(() => props.conversationStats?.allCount || 0);
const formattedAllCount = computed(() => formatNumber(allCount.value));

const toggleConversationLayout = () => {
  const { LAYOUT_TYPES } = wootConstants;
  const {
    conversation_display_type: conversationDisplayType = LAYOUT_TYPES.CONDENSED,
  } = uiSettings.value;
  const newViewType =
    conversationDisplayType === LAYOUT_TYPES.CONDENSED
      ? LAYOUT_TYPES.EXPANDED
      : LAYOUT_TYPES.CONDENSED;
  updateUISettings({
    conversation_display_type: newViewType,
    previously_used_conversation_display_type: newViewType,
  });
};
</script>

<template>
  <div
    class="pat-list-head"
    :class="{
      'pat-list-head--bordered': hasAppliedFiltersOrActiveFolders,
    }"
  >
    <div class="pat-list-head-top">
      <div class="pat-list-title-wrap min-w-0">
        <h1 class="pat-list-title truncate text-n-slate-12" :title="pageTitle">
          {{ pageTitle }}
        </h1>
        <span
          v-if="
            allCount > 0 && hasAppliedFiltersOrActiveFolders && !isListLoading
          "
          class="pat-list-count shrink-0"
          :title="allCount"
        >
          {{ formattedAllCount }}
        </span>
        <span
          v-if="!hasAppliedFiltersOrActiveFolders"
          class="pat-list-count pat-list-count--status shrink-0 capitalize"
        >
          {{ $t(`CHAT_LIST.CHAT_STATUS_FILTER_ITEMS.${activeStatus}.TEXT`) }}
        </span>
      </div>
      <div class="pat-list-actions flex items-center gap-1 shrink-0">
        <ComposeConversation>
          <template #trigger>
            <button type="button" class="patra-new-conv-btn">+ New</button>
          </template>
        </ComposeConversation>
        <template v-if="hasAppliedFilters && !hasActiveFolders">
          <div class="relative">
            <NextButton
              v-tooltip.top-end="$t('FILTER.CUSTOM_VIEWS.ADD.SAVE_BUTTON')"
              icon="i-lucide-save"
              slate
              xs
              faded
              @click="emit('addFolders')"
            />
            <div
              id="saveFilterTeleportTarget"
              class="absolute z-50 mt-2"
              :class="{ 'ltr:right-0 rtl:left-0': isOnExpandedLayout }"
            />
          </div>
          <NextButton
            v-tooltip.top-end="$t('FILTER.CLEAR_BUTTON_LABEL')"
            icon="i-lucide-circle-x"
            ruby
            faded
            xs
            @click="emit('resetFilters')"
          />
        </template>
        <template v-if="hasActiveFolders">
          <div class="relative">
            <NextButton
              id="toggleConversationFilterButton"
              v-tooltip.top-end="$t('FILTER.CUSTOM_VIEWS.EDIT.EDIT_BUTTON')"
              icon="i-lucide-pen-line"
              slate
              xs
              faded
              @click="emit('filtersModal')"
            />
            <div
              id="conversationFilterTeleportTarget"
              class="absolute z-50 mt-2"
              :class="{ 'ltr:right-0 rtl:left-0': isOnExpandedLayout }"
            />
          </div>
          <NextButton
            id="toggleConversationFilterButton"
            v-tooltip.top-end="$t('FILTER.CUSTOM_VIEWS.DELETE.DELETE_BUTTON')"
            icon="i-lucide-trash-2"
            ruby
            xs
            faded
            @click="emit('deleteFolders')"
          />
        </template>
        <div v-else class="relative">
          <NextButton
            id="toggleConversationFilterButton"
            v-tooltip.right="$t('FILTER.TOOLTIP_LABEL')"
            icon="i-lucide-list-filter"
            slate
            xs
            faded
            @click="emit('filtersModal')"
          />
          <div
            id="conversationFilterTeleportTarget"
            class="absolute z-50 mt-2"
            :class="{ 'ltr:right-0 rtl:left-0': isOnExpandedLayout }"
          />
        </div>
        <ConversationBasicFilter
          v-if="!hasAppliedFiltersOrActiveFolders"
          :is-on-expanded-layout="isOnExpandedLayout"
          @change-filter="onBasicFilterChange"
        />
        <SwitchLayout
          :is-on-expanded-layout="isOnExpandedLayout"
          @toggle="toggleConversationLayout"
        />
      </div>
    </div>
  </div>
</template>

<style scoped>
.pat-list-head {
  padding: 18px 16px 10px;
  flex-shrink: 0;
}

.pat-list-head--bordered {
  border-bottom: 1px solid var(--border, #171520);
}

.pat-list-head-top {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
}

.pat-list-title-wrap {
  display: flex;
  align-items: center;
  gap: 9px;
  min-width: 0;
}

.pat-list-title {
  font-family: 'Space Grotesk', sans-serif;
  font-weight: 600;
  font-size: 19px;
  letter-spacing: -0.01em;
  margin: 0;
}

.pat-list-count {
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  font-size: 11px;
  font-weight: 600;
  color: var(--patra-2, #8b5cf6);
  background: rgba(110, 86, 207, 0.14);
  padding: 3px 9px;
  border-radius: 20px;
}

.pat-list-count--status {
  color: var(--text-2, #a8a6b6);
  background: var(--surface-3, #1b1925);
}

.patra-new-conv-btn {
  padding: 4px 12px;
  border-radius: 6px;
  font-size: 12px;
  font-weight: 600;
  background: linear-gradient(135deg, #6e56cf, #5b45b0);
  color: white;
  border: none;
  cursor: pointer;
}
</style>
