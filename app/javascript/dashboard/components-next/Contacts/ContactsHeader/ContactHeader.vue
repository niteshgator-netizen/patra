<script setup>
import ContactSortMenu from './components/ContactSortMenu.vue';
import ContactMoreActions from './components/ContactMoreActions.vue';
import ComposeConversation from 'dashboard/components-next/NewConversation/ComposeConversation.vue';

defineProps({
  showSearch: { type: Boolean, default: true },
  searchValue: { type: String, default: '' },
  headerTitle: { type: String, required: true },
  buttonLabel: { type: String, default: '' },
  totalItems: { type: Number, default: 0 },
  activeSort: { type: String, default: 'last_activity_at' },
  activeOrdering: { type: String, default: '' },
  isSegmentsView: { type: Boolean, default: false },
  hasActiveFilters: { type: Boolean, default: false },
  isLabelView: { type: Boolean, default: false },
  isActiveView: { type: Boolean, default: false },
});

const emit = defineEmits([
  'search',
  'filter',
  'update:sort',
  'add',
  'import',
  'export',
  'createSegment',
  'deleteSegment',
]);
</script>

<template>
  <div class="list-head">
    <div class="list-head-top">
      <div class="list-title display">
        {{ headerTitle }}
        <span v-if="totalItems" class="count">{{ totalItems }}</span>
      </div>
      <div class="list-head-actions">
        <div v-if="!isLabelView && !isActiveView" class="icon-btn-wrap">
          <button
            id="toggleContactsFilterButton"
            type="button"
            class="icon-btn"
            :title="
              isSegmentsView
                ? $t('CONTACTS_LAYOUT.FILTER.EDIT_SEGMENT')
                : $t('CONTACTS_LAYOUT.FILTER.TITLE')
            "
            @click="emit('filter')"
          >
            <svg
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="2"
            >
              <path d="M3 6h18M7 12h10M11 18h2" />
            </svg>
            <span
              v-if="hasActiveFilters && !isSegmentsView"
              class="filter-dot"
            />
          </button>
          <slot name="filter" />
        </div>
        <ContactMoreActions
          class="patra-more-actions"
          @add="emit('add')"
          @import="emit('import')"
          @export="emit('export')"
        />
        <ContactSortMenu
          :active-sort="activeSort"
          :active-ordering="activeOrdering"
          class="patra-sort-menu"
          @update:sort="emit('update:sort', $event)"
        />
        <button
          v-if="
            hasActiveFilters && !isSegmentsView && !isLabelView && !isActiveView
          "
          type="button"
          class="icon-btn"
          @click="emit('createSegment')"
        >
          <svg
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
          >
            <path
              d="M19 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11l5 5v11a2 2 0 0 1-2 2z"
            />
            <polyline points="17 21 17 13 7 13 7 21" />
            <polyline points="7 3 7 8 15 8" />
          </svg>
        </button>
        <button
          v-if="isSegmentsView && !isLabelView && !isActiveView"
          type="button"
          class="icon-btn danger"
          @click="emit('deleteSegment')"
        >
          <svg
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
          >
            <polyline points="3 6 5 6 21 6" />
            <path d="M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6" />
          </svg>
        </button>
      </div>
    </div>
    <div v-if="showSearch" class="search">
      <svg
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        stroke-width="2"
      >
        <circle cx="11" cy="11" r="8" />
        <path d="M21 21l-4.35-4.35" />
      </svg>
      <input
        :value="searchValue"
        type="search"
        :placeholder="$t('CONTACTS_LAYOUT.HEADER.SEARCH_PLACEHOLDER_PATRA')"
        @input="emit('search', $event.target.value)"
      />
    </div>
    <div class="list-head-compose">
      <ComposeConversation>
        <template #trigger>
          <button type="button" class="btn primary">
            <svg
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="2"
            >
              <path
                d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"
              />
            </svg>
            {{ buttonLabel }}
          </button>
        </template>
      </ComposeConversation>
    </div>
  </div>
</template>

<style scoped>
.patra-more-actions :deep(button),
.patra-sort-menu :deep(button) {
  width: 32px;
  height: 32px;
  border-radius: 9px;
  border: 1px solid var(--border);
  background: var(--surface-2);
  color: var(--text-2);
}

.filter-dot {
  position: absolute;
  top: 4px;
  right: 4px;
  width: 7px;
  height: 7px;
  border-radius: 50%;
  background: var(--patra-2);
}

.icon-btn-wrap {
  position: relative;
}

.list-head-compose {
  padding: 0 16px 10px;
}

.list-head-actions {
  display: flex;
  gap: 6px;
  align-items: center;
}
</style>
