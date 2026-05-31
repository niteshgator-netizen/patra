<script setup>
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import KnowledgeArticlesAPI from 'dashboard/api/knowledgeArticles';

const { t } = useI18n();
const articles = ref([]);
const editing = ref(null);
const searchQuery = ref('');

const load = async () => {
  const { data } = await KnowledgeArticlesAPI.get();
  articles.value = data;
};

const save = async () => {
  if (editing.value.id) {
    await KnowledgeArticlesAPI.update(editing.value.id, editing.value);
  } else {
    await KnowledgeArticlesAPI.create(editing.value);
  }
  editing.value = null;
  await load();
};

const search = async () => {
  const { data } = await KnowledgeArticlesAPI.search(searchQuery.value);
  articles.value = data;
};

const draftFromConversations = async id => {
  await KnowledgeArticlesAPI.draftFromConversations(id);
  await load();
};

onMounted(load);
</script>

<template>
  <div class="pat-page-wrap">
    <div class="pat-page-main">
      <div class="flex flex-col gap-4 p-6">
        <header class="flex items-center justify-between">
          <h1 class="text-2xl font-semibold">
            {{ $t('PATRA.KNOWLEDGE.TITLE') }}
          </h1>
          <button
            class="px-3 py-2 text-sm text-white rounded-lg bg-n-brand"
            @click="editing = { title: '', content: '', published: false }"
          >
            {{ $t('PATRA.KNOWLEDGE.NEW') }}
          </button>
        </header>

        <div class="flex gap-2">
          <input
            v-model="searchQuery"
            class="flex-1 p-2 border rounded-lg border-n-weak"
            :placeholder="$t('PATRA.KNOWLEDGE.SEARCH')"
            @keyup.enter="search"
          />
        </div>

        <div v-if="editing" class="p-4 border rounded-xl border-n-weak">
          <input
            v-model="editing.title"
            class="w-full p-2 mb-2 border rounded-lg border-n-weak"
          />
          <textarea
            v-model="editing.content"
            class="w-full p-2 border rounded-lg border-n-weak"
            rows="8"
          />
          <div class="flex gap-2 mt-2">
            <button
              class="px-3 py-1 text-sm text-white rounded-lg bg-n-brand"
              @click="save"
            >
              {{ $t('PATRA.KNOWLEDGE.SAVE') }}
            </button>
            <button
              class="px-3 py-1 text-sm border rounded-lg border-n-weak"
              @click="editing = null"
            >
              {{ $t('PATRA.KNOWLEDGE.CANCEL') }}
            </button>
          </div>
        </div>

        <div
          v-for="article in articles"
          :key="article.id"
          class="p-4 border rounded-xl border-n-weak"
        >
          <div class="flex items-center justify-between">
            <h3 class="font-medium">{{ article.title }}</h3>
            <div class="flex gap-2">
              <button
                class="text-xs text-n-brand"
                @click="editing = { ...article }"
              >
                {{ $t('PATRA.KNOWLEDGE.EDIT') }}
              </button>
              <button
                class="text-xs text-n-brand"
                @click="draftFromConversations(article.id)"
              >
                {{ $t('PATRA.KNOWLEDGE.DRAFT_FROM_CONVERSATIONS') }}
              </button>
            </div>
          </div>
          <p class="mt-1 text-xs text-n-slate-11">
            {{ article.category }} · 👍 {{ article.helpful_count }}
          </p>
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
