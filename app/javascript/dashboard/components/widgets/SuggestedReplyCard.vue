<script setup>
import { ref, watch } from 'vue';
import PatraAiAPI from 'dashboard/api/patraAi';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';

const props = defineProps({
  conversationId: { type: [Number, String], required: true },
});

const emit = defineEmits(['apply']);
const suggestion = ref('');
const loading = ref(false);
const dismissed = ref(false);

const fetchSuggestion = async () => {
  if (!props.conversationId) return;
  loading.value = true;
  dismissed.value = false;
  try {
    const { data } = await PatraAiAPI.copilotSuggestion(
      props.conversationId,
      ''
    );
    suggestion.value = data?.suggestion || data?.reply || '';
  } catch {
    suggestion.value = '';
  } finally {
    loading.value = false;
  }
};

watch(() => props.conversationId, fetchSuggestion, { immediate: true });

/* C1: Apply inserts the suggested reply into the composer via the same bus
   event the copilot uses (Editor.vue listens for INSERT_INTO_RICH_EDITOR). */
const applySuggestion = () => {
  emitter.emit(BUS_EVENTS.INSERT_INTO_RICH_EDITOR, suggestion.value);
  emit('apply', suggestion.value);
};

const editSuggestion = () => {
  applySuggestion();
  const el = document.querySelector(
    '.reply-box--container textarea, .reply-box--container .ProseMirror'
  );
  if (el) el.focus();
};

const dismiss = () => {
  dismissed.value = true;
};
</script>

<template>
  <div v-if="suggestion && !dismissed" class="suggested-reply-card">
    <div class="sr-header">
      <span class="sr-dot" />
      <span class="sr-title">{{ $t('PATRA.AI_CARD.SUGGESTED_REPLY') }}</span>
      <button class="sr-dismiss" @click="dismiss">✕</button>
    </div>
    <p class="sr-text">{{ suggestion }}</p>
    <div class="sr-actions">
      <button class="sr-use" @click="applySuggestion">
        {{ $t('PATRA.AI_CARD.USE_REPLY') }}
      </button>
      <button class="sr-edit" @click="editSuggestion">
        {{ $t('PATRA.AI_CARD.EDIT') }}
      </button>
    </div>
  </div>
</template>

<style scoped>
.suggested-reply-card {
  margin: 8px 12px;
  padding: 10px 12px;
  border-radius: 10px;
  background: rgba(110, 86, 207, 0.06);
  border: 1px solid rgba(110, 86, 207, 0.18);
  font-size: 12px;
}
.sr-header {
  display: flex;
  align-items: center;
  gap: 6px;
  margin-bottom: 6px;
}
.sr-dot {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  background: #8b5cf6;
  flex-shrink: 0;
}
.sr-title {
  font-size: 11px;
  font-weight: 600;
  color: #a78bfa;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  flex: 1;
}
.sr-dismiss {
  background: none;
  border: none;
  color: #75727f;
  cursor: pointer;
  font-size: 14px;
  padding: 0;
}
/* A7: tokenized — hardcoded dark-theme hex broke light mode */
.sr-text {
  color: var(--text, #1a1a24);
  line-height: 1.5;
  margin: 4px 0 8px;
}
.sr-actions {
  display: flex;
  gap: 6px;
}
.sr-use {
  flex: 1;
  padding: 6px 0;
  border-radius: 6px;
  border: none;
  background: linear-gradient(135deg, #6e56cf, #5b45b0);
  color: white;
  font-size: 12px;
  font-weight: 600;
  cursor: pointer;
}
.sr-use:hover {
  opacity: 0.9;
}
.sr-edit {
  padding: 6px 12px;
  border-radius: 6px;
  border: 1px solid rgba(110, 86, 207, 0.3);
  background: transparent;
  color: #a78bfa;
  font-size: 12px;
  font-weight: 600;
  cursor: pointer;
}
</style>
