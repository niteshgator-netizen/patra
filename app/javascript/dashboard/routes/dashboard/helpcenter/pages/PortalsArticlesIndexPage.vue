<script setup>
import { computed, ref, onMounted, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useMapGetter, useStore } from 'dashboard/composables/store.js';
import allLocales from 'shared/constants/locales.js';
import { getArticleStatus } from 'dashboard/helper/portalHelper.js';
import ArticlesPage from 'dashboard/components-next/HelpCenter/Pages/ArticlePage/ArticlesPage.vue';

const route = useRoute();
const store = useStore();

const pageNumber = ref(1);

const allArticles = useMapGetter('articles/allArticles');
const articlesSortedByPosition = useMapGetter(
  'articles/allArticlesSortedByPosition'
);
const categories = useMapGetter('categories/allCategories');
const meta = useMapGetter('articles/getMeta');
const portalMeta = useMapGetter('portals/getMeta');
const currentUserId = useMapGetter('getCurrentUserID');
const getPortalBySlug = useMapGetter('portals/portalBySlug');

const selectedPortalSlug = computed(() => route.params.portalSlug);
const selectedCategorySlug = computed(() => route.params.categorySlug);
const status = computed(() => getArticleStatus(route.params.tab));

const author = computed(() =>
  route.params.tab === 'mine' ? currentUserId.value : null
);

const activeLocale = computed(() => route.params.locale);
const portal = computed(() => getPortalBySlug.value(selectedPortalSlug.value));
const allowedLocales = computed(() => {
  if (!portal.value) {
    return [];
  }
  const { allowed_locales: allAllowedLocales } = portal.value.config;
  return allAllowedLocales.map(locale => {
    return {
      id: locale.code,
      name: allLocales[locale.code],
      code: locale.code,
    };
  });
});

const defaultPortalLocale = computed(() => {
  return portal.value?.meta?.default_locale;
});

const selectedLocaleInPortal = computed(() => {
  return route.params.locale || defaultPortalLocale.value;
});

const isCategoryArticles = computed(() => {
  return (
    route.name === 'portals_categories_articles_index' ||
    route.name === 'portals_categories_articles_edit' ||
    route.name === 'portals_categories_index'
  );
});

// Use position-sorted articles for category views and categories filter view (where drag reorder is enabled)
const articles = computed(() =>
  isCategoryArticles.value ? articlesSortedByPosition.value : allArticles.value
);

const fetchArticles = ({ pageNumber: pageNumberParam } = {}) => {
  store.dispatch('articles/index', {
    pageNumber: pageNumberParam || pageNumber.value,
    portalSlug: selectedPortalSlug.value,
    locale: activeLocale.value,
    status: status.value,
    authorId: author.value,
    categorySlug: selectedCategorySlug.value,
  });
};

const onPageChange = pageNumberParam => {
  fetchArticles({ pageNumber: pageNumberParam });
};

const fetchPortalAndItsCategories = async locale => {
  await store.dispatch('portals/index');
  const selectedPortalParam = {
    portalSlug: selectedPortalSlug.value,
    locale: locale || selectedLocaleInPortal.value,
  };
  store.dispatch('portals/show', selectedPortalParam);
  store.dispatch('categories/index', selectedPortalParam);
  store.dispatch('agents/get');
};

onMounted(() => {
  fetchArticles();
});

watch(
  () => route.params,
  () => {
    pageNumber.value = 1;
    fetchArticles();
  },
  { deep: true, immediate: true }
);
</script>

<template>
  <div class="pat-page-wrap">
    <div class="pat-page-main">
      <div class="w-full h-full">
        <ArticlesPage
          v-if="portal"
          :articles="articles"
          :portal-name="portal.name"
          :categories="categories"
          :allowed-locales="allowedLocales"
          :meta="meta"
          :portal-meta="portalMeta"
          :is-category-articles="isCategoryArticles"
          @page-change="onPageChange"
          @fetch-portal="fetchPortalAndItsCategories"
          @refresh-articles="fetchArticles"
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
