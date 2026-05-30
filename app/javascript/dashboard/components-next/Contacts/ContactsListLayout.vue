<script setup>
import { computed, ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';

import ContactListHeaderWrapper from 'dashboard/components-next/Contacts/ContactsHeader/ContactListHeaderWrapper.vue';
import ContactsActiveFiltersPreview from 'dashboard/components-next/Contacts/ContactsHeader/components/ContactsActiveFiltersPreview.vue';
import ContactsLoadMore from 'dashboard/components-next/Contacts/ContactsLoadMore.vue';

const props = defineProps({
  searchValue: { type: String, default: '' },
  headerTitle: { type: String, default: '' },
  showPaginationFooter: { type: Boolean, default: true },
  currentPage: { type: Number, default: 1 },
  totalItems: { type: Number, default: 100 },
  itemsPerPage: { type: Number, default: 15 },
  activeSort: { type: String, default: '' },
  activeOrdering: { type: String, default: '' },
  activeSegment: { type: Object, default: null },
  segmentsId: { type: [String, Number], default: 0 },
  hasAppliedFilters: { type: Boolean, default: false },
  isFetchingList: { type: Boolean, default: false },
  useInfiniteScroll: { type: Boolean, default: false },
  hasMore: { type: Boolean, default: false },
  isLoadingMore: { type: Boolean, default: false },
});

const emit = defineEmits([
  'update:currentPage',
  'update:sort',
  'search',
  'applyFilter',
  'clearFilters',
  'loadMore',
]);

const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const contactListHeaderWrapper = ref(null);

const isNotSegmentView = computed(() => {
  return route.name !== 'contacts_dashboard_segments_index';
});

const isActiveView = computed(() => {
  return route.name === 'contacts_dashboard_active';
});

const isLabelView = computed(
  () => route.name === 'contacts_dashboard_labels_index'
);

const showActiveFiltersPreview = computed(() => {
  return (
    (props.hasAppliedFilters || !isNotSegmentView.value) &&
    !props.isFetchingList &&
    !isLabelView.value &&
    !isActiveView.value
  );
});

const totalPages = computed(() =>
  Math.ceil(props.totalItems / props.itemsPerPage)
);

const startItem = computed(
  () => (props.currentPage - 1) * props.itemsPerPage + 1
);

const endItem = computed(() =>
  Math.min(startItem.value + props.itemsPerPage - 1, props.totalItems)
);

const pageNumbers = computed(() => {
  const pages = [];
  const max = Math.min(totalPages.value, 5);
  let start = Math.max(1, props.currentPage - 2);
  const end = Math.min(totalPages.value, start + max - 1);
  start = Math.max(1, end - max + 1);
  for (let i = start; i <= end; i += 1) pages.push(i);
  return pages;
});

const showingLabel = computed(() =>
  t('CONTACTS_LAYOUT.PAGINATION_FOOTER.SHOWING', {
    startItem: startItem.value,
    endItem: endItem.value,
    totalItems: props.totalItems,
  })
);

const updateCurrentPage = page => {
  emit('update:currentPage', page);
};

const openFilter = () => {
  contactListHeaderWrapper.value?.onToggleFilters();
};

const showLoadMore = computed(() => {
  return props.useInfiniteScroll && props.hasMore;
});

const showPagination = computed(() => {
  return !props.useInfiniteScroll && props.showPaginationFooter;
});

const goToFilterTab = viewName => {
  if (route.name === viewName) return;
  router.push({
    name: viewName,
    params: { accountId: route.params.accountId },
    query: { page: 1 },
  });
};

const goToTaggedTab = () => {
  router.push({
    name: 'contacts_dashboard_labels_index',
    params: {
      accountId: route.params.accountId,
      label: 'ai-off',
    },
    query: { page: 1 },
  });
};

const isTabActive = name => route.name === name;
</script>

<template>
  <div class="list">
    <ContactListHeaderWrapper
      ref="contactListHeaderWrapper"
      :show-search="isNotSegmentView && !isActiveView"
      :search-value="searchValue"
      :active-sort="activeSort"
      :active-ordering="activeOrdering"
      :header-title="headerTitle"
      :total-items="totalItems"
      :active-segment="activeSegment"
      :segments-id="segmentsId"
      :has-applied-filters="hasAppliedFilters"
      :is-label-view="isLabelView"
      :is-active-view="isActiveView"
      @update:sort="emit('update:sort', $event)"
      @search="emit('search', $event)"
      @apply-filter="emit('applyFilter', $event)"
      @clear-filters="emit('clearFilters')"
    />
    <div v-if="isNotSegmentView && !isActiveView" class="subnav-wrap">
      <div class="subnav">
        <button
          type="button"
          :class="{ active: isTabActive('contacts_dashboard_index') }"
          @click="goToFilterTab('contacts_dashboard_index')"
        >
          {{ t('CONTACTS_LAYOUT.FILTER_TABS.ALL') }}
        </button>
        <button
          type="button"
          :class="{ active: isTabActive('contacts_dashboard_active') }"
          @click="goToFilterTab('contacts_dashboard_active')"
        >
          {{ t('CONTACTS_LAYOUT.FILTER_TABS.ACTIVE') }}
        </button>
        <button
          type="button"
          :class="{
            active:
              isTabActive('contacts_dashboard_labels_index') &&
              route.params.label === 'ai-off',
          }"
          @click="goToTaggedTab"
        >
          {{ t('CONTACTS_LAYOUT.FILTER_TABS.TAGGED') }}
          <span class="lbl-dot" />
          {{ t('CONTACTS_LAYOUT.FILTER_TABS.AI_OFF') }}
        </button>
      </div>
    </div>
    <div class="contacts">
      <ContactsActiveFiltersPreview
        v-if="showActiveFiltersPreview"
        :active-segment="activeSegment"
        class="filters-preview"
        @clear-filters="emit('clearFilters')"
        @open-filter="openFilter"
      />
      <slot name="default" />
      <ContactsLoadMore
        v-if="showLoadMore"
        :is-loading="isLoadingMore"
        @load-more="emit('loadMore')"
      />
    </div>
    <div v-if="showPagination" class="list-foot">
      <span>{{ showingLabel }}</span>
      <div class="pager">
        <button
          type="button"
          :disabled="currentPage <= 1"
          @click="updateCurrentPage(currentPage - 1)"
        >
          {{ t('CONTACTS_LAYOUT.PAGER.PREV') }}
        </button>
        <button
          v-for="page in pageNumbers"
          :key="page"
          type="button"
          :class="{ active: page === currentPage }"
          @click="updateCurrentPage(page)"
        >
          {{ page }}
        </button>
        <button
          type="button"
          :disabled="currentPage >= totalPages"
          @click="updateCurrentPage(currentPage + 1)"
        >
          {{ t('CONTACTS_LAYOUT.PAGER.NEXT') }}
        </button>
      </div>
    </div>
  </div>
</template>
