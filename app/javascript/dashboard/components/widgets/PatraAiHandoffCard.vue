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

const show = computed(() => true);

const sentimentClass = computed(() => {
  const s = attrs.value.sentiment?.toLowerCase();
  if (s === 'frustrated' || s === 'angry') return 'ai-hc-sentiment-negative';
  if (s === 'positive' || s === 'happy') return 'ai-hc-sentiment-positive';
  return '';
});

const scrollToFirstAiMessage = () => {
  const msgs = document.querySelectorAll('.patra-conv-bubble--agent');
  if (msgs.length) msgs[0].scrollIntoView({ behavior: 'smooth', block: 'center' });
};

const askPatraAi = () => {
  const el = document.querySelector(
    '.reply-box--container textarea, .reply-box--container .ProseMirror'
  );
  if (el) {
    el.focus();
  }
};
</script>

<template>
  <div class="ai-handoff-card">
    <div class="ai-hc-header">
      <span class="ai-dot" :class="aiOff ? 'dot-off' : 'dot-on'" />
      <span class="ai-hc-title">
        {{ aiOff ? 'Handed to you by Patra AI' : 'Patra AI — Active' }}
      </span>
    </div>
    <div v-if="attrs.last_intent_confidence" class="ai-hc-intent">
      <span class="ai-hc-label">Confidence</span>
      <span class="ai-hc-value">{{ Math.round(attrs.last_intent_confidence * 100) }}%</span>
    </div>
    <div v-if="intentLabel" class="ai-hc-intent">
      <span class="ai-hc-label">Intent</span>
      <span class="ai-hc-value">{{ intentLabel }}</span>
    </div>
    <div v-if="attrs.last_intent_reason" class="ai-hc-intent">
      <span class="ai-hc-label">Reason</span>
      <span class="ai-hc-value">{{ attrs.last_intent_reason }}</span>
    </div>
    <div v-if="attrs.sentiment" class="ai-hc-intent">
      <span class="ai-hc-label">Sentiment</span>
      <span class="ai-hc-value" :class="sentimentClass">{{ attrs.sentiment }}</span>
    </div>
    <div v-if="attrs.safety_flags" class="ai-hc-intent">
      <span class="ai-hc-label">Safety</span>
      <span class="ai-hc-value">{{ attrs.safety_flags }}</span>
    </div>
    <div v-if="attrs.detected_entities" class="ai-hc-intent">
      <span class="ai-hc-label">Entities</span>
      <span class="ai-hc-value">{{ attrs.detected_entities }}</span>
    </div>
    <div v-if="attrs.awaiting_load_amount" class="ai-hc-intent">
      <span class="ai-hc-label">Awaiting amount</span>
      <span class="ai-hc-value">${{ attrs.awaiting_load_amount }}</span>
    </div>
    <div v-if="aiOff" class="ai-hc-intent" style="margin-top: 6px">
      <a
        href="#"
        class="ai-hc-session-link"
        @click.prevent="scrollToFirstAiMessage"
      >
        View full AI session →
      </a>
    </div>
    <button class="ai-hc-ask-btn" @click="askPatraAi">Ask Patra AI</button>
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
.ai-hc-sentiment-negative {
  color: #f85149;
}
.ai-hc-sentiment-positive {
  color: #3fb950;
}
.ai-hc-session-link {
  color: #8b5cf6;
  font-size: 11px;
  text-decoration: none;
}
.ai-hc-session-link:hover {
  text-decoration: underline;
}
.ai-hc-ask-btn {
  width: 100%;
  margin-top: 8px;
  padding: 5px 0;
  border-radius: 6px;
  border: 1px solid rgba(110, 86, 207, 0.3);
  background: transparent;
  color: #a78bfa;
  font-size: 11px;
  font-weight: 600;
  cursor: pointer;
}
.ai-hc-ask-btn:hover {
  background: rgba(110, 86, 207, 0.08);
}
</style>
