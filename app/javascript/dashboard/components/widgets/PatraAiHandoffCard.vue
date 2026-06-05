<script setup>
import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';

const props = defineProps({
  conversationId: { type: [Number, String], required: true },
});

const conversations = useMapGetter('getAllConversations');

const conversation = computed(() =>
  conversations.value?.find(c => c.id === Number(props.conversationId))
);

const aiOff = computed(() =>
  (conversation.value?.labels || []).includes('ai-off')
);

const attrs = computed(() =>
  conversation.value?.additional_attributes || {}
);

const intentLabel = computed(() => {
  if (attrs.value.awaiting_load_amount) return 'Load deposit — awaiting amount';
  if (attrs.value.sender_match_state === 'awaiting_details')
    return 'Payment match — awaiting details';
  if (attrs.value.sender_match_state === 'matched') return 'Payment matched ✓';
  return null;
});

const show = computed(() => aiOff.value || !!intentLabel.value);
</script>

<template>
  <div v-if="show" class="ai-handoff-card">
    <div class="ai-hc-header">
      <span class="ai-dot" :class="aiOff ? 'dot-off' : 'dot-on'" />
      <span class="ai-hc-title">
        {{ aiOff ? 'Human — AI Paused' : 'Patra AI — Active' }}
      </span>
    </div>
    <div v-if="intentLabel" class="ai-hc-intent">
      <span class="ai-hc-label">Last intent</span>
      <span class="ai-hc-value">{{ intentLabel }}</span>
    </div>
    <div v-if="attrs.awaiting_load_amount" class="ai-hc-intent">
      <span class="ai-hc-label">Awaiting amount</span>
      <span class="ai-hc-value">${{ attrs.awaiting_load_amount }}</span>
    </div>
  </div>
</template>

<style scoped>
.ai-handoff-card {
  margin: 8px 12px;
  padding: 10px 12px;
  border-radius: 10px;
  background: rgba(110, 86, 207, 0.08);
  border: 1px solid rgba(110, 86, 207, 0.22);
  font-size: 12px;
}
.ai-hc-header {
  display: flex;
  align-items: center;
  gap: 6px;
  font-weight: 600;
  color: #a78bfa;
  margin-bottom: 6px;
}
.ai-dot {
  width: 7px;
  height: 7px;
  border-radius: 50%;
  flex-shrink: 0;
}
.dot-on {
  background: #22c55e;
}
.dot-off {
  background: #f85149;
}
.ai-hc-title {
  font-size: 11px;
  text-transform: uppercase;
  letter-spacing: 0.05em;
}
.ai-hc-intent {
  display: flex;
  justify-content: space-between;
  gap: 8px;
  padding: 3px 0;
  border-top: 1px solid rgba(110, 86, 207, 0.12);
  margin-top: 4px;
}
.ai-hc-label {
  color: #75727f;
}
.ai-hc-value {
  color: #ededf2;
  font-weight: 500;
  text-align: right;
}
</style>
