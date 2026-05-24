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
  <div class="flex flex-col gap-4 p-6">
    <header class="flex items-center justify-between">
      <h1 class="text-2xl font-semibold">{{ $t('PATRA.KNOWLEDGE.TITLE') }}</h1>
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
      <input v-model="editing.title" class="w-full p-2 mb-2 border rounded-lg border-n-weak" />
      <textarea v-model="editing.content" class="w-full p-2 border rounded-lg border-n-weak" rows="8" />
      <div class="flex gap-2 mt-2">
        <button class="px-3 py-1 text-sm text-white rounded-lg bg-n-brand" @click="save">
          {{ $t('PATRA.KNOWLEDGE.SAVE') }}
        </button>
        <button class="px-3 py-1 text-sm border rounded-lg border-n-weak" @click="editing = null">
          {{ $t('PATRA.KNOWLEDGE.CANCEL') }}
        </button>
      </div>
    </div>

    <div v-for="article in articles" :key="article.id" class="p-4 border rounded-xl border-n-weak">
      <div class="flex items-center justify-between">
        <h3 class="font-medium">{{ article.title }}</h3>
        <div class="flex gap-2">
          <button class="text-xs text-n-brand" @click="editing = { ...article }">
            {{ $t('PATRA.KNOWLEDGE.EDIT') }}
          </button>
          <button class="text-xs text-n-brand" @click="draftFromConversations(article.id)">
            {{ $t('PATRA.KNOWLEDGE.DRAFT_FROM_CONVERSATIONS') }}
          </button>
        </div>
      </div>
      <p class="mt-1 text-xs text-n-slate-11">{{ article.category }} · 👍 {{ article.helpful_count }}</p>
    </div>
  </div>
</template>
