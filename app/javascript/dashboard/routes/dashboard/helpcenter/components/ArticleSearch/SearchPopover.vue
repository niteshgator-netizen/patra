<script>
import { debounce } from '@chatwoot/utils';
import { useAlert } from 'dashboard/composables';
import { mapGetters } from 'vuex';
import allLocales from 'shared/constants/locales.js';

import SearchHeader from './Header.vue';
import SearchResults from './SearchResults.vue';
import ArticleView from './ArticleView.vue';
import ArticlesAPI from 'dashboard/api/helpCenter/articles';
import { buildPortalArticleURL } from 'dashboard/helper/portalHelper';

export default {
  name: 'ArticleSearchPopover',
  components: {
    SearchHeader,
    SearchResults,
    ArticleView,
  },
  props: {
    selectedPortalSlug: {
      type: String,
      required: true,
    },
  },
  emits: ['close', 'insert'],
  data() {
    return {
      searchQuery: '',
      isLoading: false,
      searchResults: [],
      activeId: '',
      debounceSearch: () => {},
    };
  },
  computed: {
    ...mapGetters({
      portalBySlug: 'portals/portalBySlug',
    }),
    portal() {
      return this.portalBySlug(this.selectedPortalSlug);
    },
    portalCustomDomain() {
      return this.portal?.custom_domain;
    },
    articleViewerUrl() {
      const article = this.activeArticle(this.activeId);
      if (!article) return '';
      const isDark = document.body.classList.contains('dark');

      const url = new URL(article.url);
      url.searchParams.set('show_plain_layout', 'true');

      if (isDark) {
        url.searchParams.set('theme', 'dark');
      }

      return `${url}`;
    },

    searchResultsWithUrl() {
      return this.searchResults.map(article => ({
        ...article,
        localeName: this.localeName(article.category.locale || 'en'),
        url: this.generateArticleUrl(article),
      }));
    },
  },
  mounted() {
    this.fetchArticlesByQuery(this.searchQuery);
    this.debounceSearch = debounce(this.fetchArticlesByQuery, 500, false);
  },
  methods: {
    generateArticleUrl(article) {
      return buildPortalArticleURL(
        this.selectedPortalSlug,
        '',
        '',
        article.slug,
        this.portalCustomDomain
      );
    },
    localeName(code) {
      return allLocales[code];
    },
    activeArticle(id) {
      return this.searchResultsWithUrl.find(article => article.id === id);
    },
    onSearch(query) {
      this.searchQuery = query;
      this.activeId = '';
      this.debounceSearch(query);
    },
    onClose() {
      this.$emit('close');
      this.searchQuery = '';
      this.activeId = '';
      this.searchResults = [];
    },
    async fetchArticlesByQuery(query) {
      try {
        const sort = query ? '' : 'views';
        this.isLoading = true;
        this.searchResults = [];
        const { data } = await ArticlesAPI.searchArticles({
          portalSlug: this.selectedPortalSlug,
          query,
          sort,
        });
        this.searchResults = data.payload;
        this.isLoading = true;
      } catch (error) {
        // Show something wrong message
      } finally {
        this.isLoading = false;
      }
    },
    handlePreview(id) {
      this.activeId = id;
    },
    onBack() {
      this.activeId = '';
    },
    onInsert(id) {
      const article = this.activeArticle(id || this.activeId);
      this.$emit('insert', article);
      useAlert(this.$t('HELP_CENTER.ARTICLE_SEARCH.SUCCESS_ARTICLE_INSERTED'));
      this.onClose();
    },
  },
};
</script>

<template>
  <div class="pat-page-wrap">
    <div class="pat-page-main">
      <div
        class="fixed top-0 left-0 z-50 flex items-center justify-center w-screen h-screen bg-modal-backdrop-light dark:bg-modal-backdrop-dark"
      >
        <div
          v-on-clickaway="onClose"
          class="flex flex-col px-4 pb-4 rounded-md shadow-md border border-solid border-n-weak bg-n-background z-[1000] max-w-[720px] md:w-[20rem] lg:w-[24rem] xl:w-[28rem] 2xl:w-[32rem] h-[calc(100vh-20rem)] max-h-[40rem]"
        >
          <SearchHeader
            :title="$t('HELP_CENTER.ARTICLE_SEARCH.TITLE')"
            class="w-full sticky top-0 bg-[inherit]"
            @close="onClose"
            @search="onSearch"
          />

          <ArticleView
            v-if="activeId"
            :url="articleViewerUrl"
            @back="onBack"
            @insert="onInsert"
          />
          <SearchResults
            v-else
            :search-query="searchQuery"
            :is-loading="isLoading"
            :portal-slug="selectedPortalSlug"
            :articles="searchResultsWithUrl"
            @preview="handlePreview"
            @insert="onInsert"
          />
        </div>
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
