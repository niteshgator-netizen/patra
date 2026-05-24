<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';

const props = defineProps({
  messages: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['scrollToMessage']);

const { t } = useI18n();
const { getPlainText } = useMessageFormatter();
const showPinned = ref(true);

const pinnedMessages = computed(() =>
  [...props.messages]
    .filter(message => {
      const contentAttributes =
        message.content_attributes ?? message.contentAttributes ?? {};
      return contentAttributes.pinned === true;
    })
    .sort((first, second) => {
      const firstAttributes =
        first.content_attributes ?? first.contentAttributes ?? {};
      const secondAttributes =
        second.content_attributes ?? second.contentAttributes ?? {};
      const firstPinnedAt =
        firstAttributes.pinned_at ??
        firstAttributes.pinnedAt ??
        first.created_at ??
        first.createdAt ??
        0;
      const secondPinnedAt =
        secondAttributes.pinned_at ??
        secondAttributes.pinnedAt ??
        second.created_at ??
        second.createdAt ??
        0;

      return secondPinnedAt - firstPinnedAt;
    })
);

const truncate = (content, length) => {
  const text = getPlainText(content || '');
  return text.length > length ? `${text.slice(0, length)}…` : text;
};

const senderName = message => message.sender?.name || t('CONVERSATION.BOT');

const sectionTitle = computed(() =>
  t('CONVERSATION.PINNED_MESSAGES.SECTION_TITLE', {
    count: pinnedMessages.value.length,
  })
);
</script>

<template>
  <div v-if="pinnedMessages.length" class="border-b border-n-weak">
    <button
      type="button"
      class="w-full px-4 py-2 text-xs font-medium text-n-slate-11 flex items-center gap-2"
      @click="showPinned = !showPinned"
    >
      <Icon icon="i-lucide-pin" class="size-3.5 text-amber-400" />
      {{ sectionTitle }}
      <span>{{ showPinned ? '▼' : '▶' }}</span>
    </button>
    <div v-if="showPinned" class="max-h-40 overflow-y-auto px-4 pb-2">
      <div
        v-for="message in pinnedMessages"
        :key="message.id"
        class="text-sm py-1 cursor-pointer hover:bg-n-alpha-2 rounded px-2"
        @click="emit('scrollToMessage', message.id)"
      >
        <span class="font-medium">{{ senderName(message) }}:</span>
        {{ truncate(message.content, 80) }}
      </div>
    </div>
  </div>
</template>
