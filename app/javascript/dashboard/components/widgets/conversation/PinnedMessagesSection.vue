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
  <div v-if="pinnedMessages.length" class="patra-pinned">
    <button
      type="button"
      class="patra-pinned-head"
      @click="showPinned = !showPinned"
    >
      <Icon icon="i-lucide-pin" class="patra-pinned-icon" />
      <span class="patra-pinned-title">{{ sectionTitle }}</span>
      <span class="patra-pinned-caret">{{ showPinned ? '▼' : '▶' }}</span>
    </button>
    <div v-if="showPinned" class="patra-pinned-list">
      <div
        v-for="message in pinnedMessages"
        :key="message.id"
        class="patra-pinned-item"
        @click="emit('scrollToMessage', message.id)"
      >
        <b class="patra-pinned-sender">{{ senderName(message) }}:</b>
        {{ truncate(message.content, 80) }}
      </div>
    </div>
  </div>
</template>

<style scoped>
/* Matches PATRA_APP_final.html .pinned banner (amber accent) */
.patra-pinned {
  margin: 8px 12px;
  border-radius: 11px;
  border: 1px solid rgba(227, 160, 8, 0.25);
  background: linear-gradient(135deg, rgba(227, 160, 8, 0.1), transparent);
}
.patra-pinned-head {
  display: flex;
  align-items: center;
  gap: 9px;
  width: 100%;
  padding: 9px 13px;
  font-size: 12.5px;
  font-weight: 600;
  color: #a8a6b6;
}
.patra-pinned-icon {
  width: 14px;
  height: 14px;
  color: #e3a008;
  flex-shrink: 0;
}
.patra-pinned-title {
  flex: 1;
  text-align: left;
}
.patra-pinned-caret {
  font-size: 10px;
  color: #75727f;
}
.patra-pinned-list {
  max-height: 10rem;
  overflow-y: auto;
  padding: 0 13px 9px;
}
.patra-pinned-item {
  font-size: 12.5px;
  color: #a8a6b6;
  padding: 4px 6px;
  border-radius: 7px;
  cursor: pointer;
}
.patra-pinned-item:hover {
  background: rgba(227, 160, 8, 0.08);
}
.patra-pinned-sender {
  color: #ededf2;
  font-weight: 600;
}
</style>
