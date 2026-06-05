<script setup>
import { ref, watch } from 'vue';
import PatraAiAPI from 'dashboard/api/patraAi';

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
    const { data } = await PatraAiAPI.copilotSuggestion(props.conversationId, '');
    suggestion.value = data?.suggestion || data?.reply || '';
  } catch {
    suggestion.value = '';
  } finally {
    loading.value = false;
  }
};

watch(() => props.conversationId, fetchSuggestion, { immediate: true });

const applySuggestion = () => emit('apply', suggestion.value);
const dismiss = () => { dismissed.value = true; };
</script>

<template>
  <div v-if="suggestion && !dismissed" class="suggested-reply-card">
    <div class="sr-header">
      <span class="sr-dot" />
      <span class="sr-title">Suggested reply</span>
      <button class="sr-dismiss" @click="dismiss">✕</button>
    </div>
    <p class="sr-text">{{ suggestion }}</p>
    <button class="sr-apply" @click="applySuggestion">Apply suggested reply</button>
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
.sr-header { display: flex; align-items: center; gap: 6px; margin-bottom: 6px; }
.sr-dot { width: 6px; height: 6px; border-radius: 50%; background: #8b5cf6; flex-shrink: 0; }
.sr-title { font-size: 11px; font-weight: 600; color: #a78bfa; text-transform: uppercase; letter-spacing: 0.05em; flex: 1; }
.sr-dismiss { background: none; border: none; color: #75727f; cursor: pointer; font-size: 14px; padding: 0; }
.sr-text { color: #ededf2; line-height: 1.5; margin: 4px 0 8px; }
.sr-apply {
  width: 100%;
  padding: 6px 0;
  border-radius: 6px;
  border: none;
  background: linear-gradient(135deg, #6e56cf, #5b45b0);
  color: white;
  font-size: 12px;
  font-weight: 600;
  cursor: pointer;
}
.sr-apply:hover { opacity: 0.9; }
</style>
