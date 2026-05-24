<script setup>
import { computed, ref, watch } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { emitter } from 'shared/helpers/mitt';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { MESSAGE_TYPES } from 'dashboard/components-next/message/constants';

const props = defineProps({
  conversationId: { type: [Number, String], required: true },
});

const emit = defineEmits(['close']);

const { t } = useI18n();
const store = useStore();
const { highlightContent, getPlainText } = useMessageFormatter();

const query = ref('');
const filter = ref('all');

const messages = computed(() => {
  const chat = store.getters.getSelectedChat;
  if (!chat?.messages || chat.id !== Number(props.conversationId)) return [];
  return chat.messages.filter(m => !m.content_attributes?.deleted);
});

const filteredMessages = computed(() => {
  const q = query.value.trim().toLowerCase();
  if (!q) return [];

  return messages.value
    .filter(message => {
      if (filter.value === 'incoming' && message.message_type !== MESSAGE_TYPES.INCOMING) {
        return false;
      }
      if (filter.value === 'outgoing' && message.message_type !== MESSAGE_TYPES.OUTGOING) {
        return false;
      }
      if (filter.value === 'private' && !message.private) return false;
      const text = getPlainText(message.content || '').toLowerCase();
      return text.includes(q);
    })
    .slice()
    .reverse()
    .slice(0, 50);
});

const scrollToMessage = messageId => {
  emitter.emit(BUS_EVENTS.SCROLL_TO_MESSAGE, { messageId });
  emit('close');
};

watch(query, value => {
  emitter.emit('patra:message-search-highlight', value.trim());
});

watch(
  () => props.conversationId,
  () => {
    query.value = '';
    emitter.emit('patra:message-search-highlight', '');
  }
);
</script>

<template>
  <div
    class="absolute top-full z-50 mt-1 w-full max-w-md rounded-xl border border-n-weak bg-n-solid-1 shadow-lg ltr:right-0 rtl:left-0"
  >
    <div class="flex items-center gap-2 border-b border-n-weak px-3 py-2">
      <span class="i-lucide-search size-4 text-n-slate-10 shrink-0" />
      <input
        v-model="query"
        type="search"
        class="flex-1 min-w-0 bg-transparent text-sm text-n-slate-12 outline-none placeholder:text-n-slate-10"
        :placeholder="$t('PATRA.MESSAGE_SEARCH.PLACEHOLDER')"
        autofocus
      />
      <button
        type="button"
        class="text-n-slate-10 hover:text-n-slate-12"
        :aria-label="$t('PATRA.CONVERSATION.CLOSE')"
        @click="emit('close')"
      >
        <span class="i-lucide-x size-4" />
      </button>
    </div>
    <div class="flex gap-1 px-3 py-2 border-b border-n-weak">
      <button
        v-for="option in ['all', 'incoming', 'outgoing', 'private']"
        :key="option"
        type="button"
        class="rounded-full px-2 py-0.5 text-xs font-medium border"
        :class="
          filter === option
            ? 'border-n-brand bg-n-brand/10 text-n-brand'
            : 'border-n-weak text-n-slate-11'
        "
        @click="filter = option"
      >
        {{ $t(`PATRA.MESSAGE_SEARCH.FILTER_${option.toUpperCase()}`) }}
      </button>
    </div>
    <ul class="max-h-64 overflow-y-auto py-1">
      <li
        v-for="message in filteredMessages"
        :key="message.id"
        class="cursor-pointer px-3 py-2 text-sm hover:bg-n-alpha-2"
        @click="scrollToMessage(message.id)"
      >
        <p
          class="line-clamp-2 text-n-slate-12 [&_.searchkey--highlight]:font-semibold [&_.searchkey--highlight]:text-n-brand"
          v-dompurify-html="
            highlightContent(
              getPlainText(message.content || ''),
              query,
              'searchkey--highlight'
            )
          "
        />
      </li>
      <li
        v-if="query && !filteredMessages.length"
        class="px-3 py-4 text-center text-sm text-n-slate-11"
      >
        {{ $t('PATRA.MESSAGE_SEARCH.NO_RESULTS') }}
      </li>
      <li
        v-else-if="!query"
        class="px-3 py-4 text-center text-sm text-n-slate-11"
      >
        {{ $t('PATRA.MESSAGE_SEARCH.HINT') }}
      </li>
    </ul>
  </div>
</template>
