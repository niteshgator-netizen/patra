<script setup>
import { computed } from 'vue';
import { messageTimestamp } from 'shared/helpers/timeHelper';
import BaseBubble from './Base.vue';
import { useMessageContext } from '../provider.js';

const { content, createdAt } = useMessageContext();

const readableTime = computed(() =>
  messageTimestamp(createdAt.value, 'LLL d, h:mm a')
);
</script>

<template>
  <BaseBubble
    v-tooltip.top="readableTime"
    class="patra-conv-day-sep px-3 py-1 flex min-w-0 items-center gap-2"
    data-bubble-name="activity"
  >
    <span v-dompurify-html="content" :title="content" />
  </BaseBubble>
</template>

<style scoped>
:deep(.patra-conv-day-sep) {
  background: transparent !important;
  border: none !important;
  padding: 2px 0 !important;
  text-align: center;
  width: 100%;
  justify-content: center;
  position: relative;
  font-family: 'JetBrains Mono', ui-monospace, monospace !important;
  font-size: 11px;
  /* A7: tokenized — hardcoded dark hex broke light mode */
  color: var(--text-4, #908da0);
}

:deep(.patra-conv-day-sep)::before {
  content: '';
  position: absolute;
  left: 0;
  right: 0;
  top: 50%;
  height: 1px;
  background: var(--border, #e5e3ee);
  z-index: 0;
}

:deep(.patra-conv-day-sep span) {
  background: var(--canvas, #f6f5f9);
  padding: 0 12px;
  position: relative;
  z-index: 1;
  font-family: 'JetBrains Mono', ui-monospace, monospace !important;
}
</style>
