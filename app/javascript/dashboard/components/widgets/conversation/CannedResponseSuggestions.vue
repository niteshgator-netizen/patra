<script setup>
import { computed, onMounted } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';

const props = defineProps({
  conversationId: {
    type: [Number, String],
    required: true,
  },
});

const emit = defineEmits(['insert']);

const store = useStore();
const cannedMessages = useMapGetter('getCannedResponses');

const currentChat = computed(() => store.getters.getSelectedChat);

const lastCustomerMessage = computed(() => {
  const messages = currentChat.value?.messages || [];
  const incoming = [...messages].reverse().find(m => m.message_type === 0);
  return incoming?.content?.toLowerCase() || '';
});

const KEYWORD_RULES = [
  { keywords: ['cashout', 'redeem', 'withdraw'], codes: ['cashout', 'redeem'] },
  { keywords: ['deposit', 'load', 'add funds'], codes: ['deposit', 'load'] },
  { keywords: ['sign up', 'register', 'new account'], codes: ['signup', 'register'] },
  { keywords: ['password', 'username', 'login'], codes: ['credentials', 'account'] },
  { keywords: ['bonus', 'promo'], codes: ['bonus', 'promo'] },
];

const suggestions = computed(() => {
  const text = lastCustomerMessage.value;
  if (!text) return [];

  const matchedCodes = new Set();
  KEYWORD_RULES.forEach(rule => {
    if (rule.keywords.some(kw => text.includes(kw))) {
      rule.codes.forEach(code => matchedCodes.add(code));
    }
  });

  const all = cannedMessages.value || [];
  const scored = all
    .map(item => {
      const code = item.short_code?.toLowerCase() || '';
      const content = item.content?.toLowerCase() || '';
      let score = 0;
      matchedCodes.forEach(mc => {
        if (code.includes(mc) || content.includes(mc)) score += 2;
      });
      KEYWORD_RULES.forEach(rule => {
        rule.keywords.forEach(kw => {
          if (text.includes(kw) && (code.includes(kw) || content.includes(kw))) {
            score += 1;
          }
        });
      });
      return { ...item, score };
    })
    .filter(item => item.score > 0)
    .sort((a, b) => b.score - a.score)
    .slice(0, 3);

  return scored;
});

const onSelect = item => {
  emit('insert', item.content);
};

onMounted(() => {
  store.dispatch('getCannedResponse', { searchKey: '' });
});
</script>

<template>
  <div v-if="suggestions.length" class="flex flex-wrap items-center gap-2 px-3 pb-2">
    <span class="text-xs text-n-slate-11">{{ $t('PATRA.CANNED.SUGGESTED') }}</span>
    <button
      v-for="item in suggestions"
      :key="item.id"
      type="button"
      class="rounded-full border border-n-weak bg-n-alpha-2 px-3 py-1 text-xs font-medium text-n-slate-12 hover:bg-n-alpha-3"
      @click="onSelect(item)"
    >
      /{{ item.short_code }}
    </button>
  </div>
</template>
