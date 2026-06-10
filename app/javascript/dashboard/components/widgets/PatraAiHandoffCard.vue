<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';

const props = defineProps({
  conversationId: { type: [Number, String], required: true },
});

const { t } = useI18n();

const conversations = useMapGetter('getAllConversations');

const conversation = computed(() =>
  conversations.value?.find(c => c.id === Number(props.conversationId))
);

const aiOff = computed(() =>
  (conversation.value?.labels || []).includes('ai-off')
);

const attrs = computed(() => conversation.value?.additional_attributes || {});

const intentLabel = computed(() => {
  if (attrs.value.awaiting_load_amount)
    return t('PATRA.AI_CARD.INTENT_LOAD_AWAITING');
  if (attrs.value.sender_match_state === 'awaiting_details')
    return t('PATRA.AI_CARD.INTENT_PAYMENT_AWAITING');
  if (attrs.value.sender_match_state === 'matched')
    return t('PATRA.AI_CARD.INTENT_PAYMENT_MATCHED');
  return null;
});

/* C1: render ONLY when real AI handoff data exists on the conversation —
   otherwise the card is fully hidden. */
const show = computed(() => {
  const a = attrs.value;
  return Boolean(
    intentLabel.value ||
      a.last_intent_confidence ||
      a.last_intent_reason ||
      a.cashout_sla_policy ||
      a.sentiment ||
      a.safety_flags ||
      a.detected_entities ||
      a.awaiting_load_amount ||
      a.ai_already_did ||
      a.customer_context ||
      a.ai_insight
  );
});

const sentimentClass = computed(() => {
  const s = attrs.value.sentiment?.toLowerCase();
  if (s === 'frustrated' || s === 'angry') return 'ai-hc-sentiment-negative';
  if (s === 'positive' || s === 'happy') return 'ai-hc-sentiment-positive';
  return '';
});

const scrollToFirstAiMessage = () => {
  const msgs = document.querySelectorAll('.patra-conv-bubble--agent');
  if (msgs.length)
    msgs[0].scrollIntoView({ behavior: 'smooth', block: 'center' });
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
  <div v-if="show" class="ai-handoff-card">
    <div class="ai-hc-header">
      <span class="ai-dot" :class="aiOff ? 'dot-off' : 'dot-on'" />
      <span class="ai-hc-title">
        {{ aiOff ? 'Handed to you by Patra AI' : 'Patra AI — Active' }}
      </span>
    </div>
    <div v-if="attrs.last_intent_confidence" class="ai-hc-intent">
      <span class="ai-hc-label">{{ $t('PATRA.AI_CARD.CONFIDENCE') }}</span>
      <span class="ai-hc-value">{{ Math.round(attrs.last_intent_confidence * 100) }}%</span>
    </div>
    <div v-if="intentLabel" class="ai-hc-intent">
      <span class="ai-hc-label">{{ $t('PATRA.AI_CARD.INTENT') }}</span>
      <span class="ai-hc-value">{{ intentLabel }}</span>
    </div>
    <div v-if="attrs.last_intent_reason" class="ai-hc-intent">
      <span class="ai-hc-label">{{ $t('PATRA.AI_CARD.REASON') }}</span>
      <span class="ai-hc-value">{{ attrs.last_intent_reason }}</span>
    </div>
    <div v-if="attrs.cashout_sla_policy" class="ai-hc-intent">
      <span class="ai-hc-label">{{ $t('PATRA.AI_CARD.CASHOUT_SLA') }}</span>
      <span class="ai-hc-value">{{ attrs.cashout_sla_policy }}</span>
    </div>
    <div v-if="attrs.sentiment" class="ai-hc-intent">
      <span class="ai-hc-label">{{ $t('PATRA.AI_CARD.SENTIMENT') }}</span>
      <span class="ai-hc-value" :class="sentimentClass">{{
        attrs.sentiment
      }}</span>
    </div>
    <div v-if="attrs.safety_flags" class="ai-hc-intent">
      <span class="ai-hc-label">{{ $t('PATRA.AI_CARD.SAFETY') }}</span>
      <span class="ai-hc-value">{{ attrs.safety_flags }}</span>
    </div>
    <div v-if="attrs.detected_entities" class="ai-hc-intent">
      <span class="ai-hc-label">{{ $t('PATRA.AI_CARD.ENTITIES') }}</span>
      <span class="ai-hc-value">{{ attrs.detected_entities }}</span>
    </div>
    <div v-if="attrs.awaiting_load_amount" class="ai-hc-intent">
      <span class="ai-hc-label">{{ $t('PATRA.AI_CARD.AWAITING_AMOUNT') }}</span>
      <span class="ai-hc-value">${{ attrs.awaiting_load_amount }}</span>
    </div>
    <div v-if="aiOff" class="ai-hc-intent" style="margin-top: 6px">
      <a
        href="#"
        class="ai-hc-session-link"
        @click.prevent="scrollToFirstAiMessage"
      >
        {{ $t('PATRA.AI_CARD.VIEW_FULL_SESSION') }}
      </a>
    </div>

    <div v-if="attrs.ai_already_did" class="ai-hc-section">
      <div class="ai-hc-section-title">
        {{ $t('PATRA.AI_CARD.AI_ALREADY_DID') }}
      </div>
      <div class="ai-hc-section-text">{{ attrs.ai_already_did }}</div>
    </div>

    <div v-if="attrs.customer_context" class="ai-hc-section">
      <div class="ai-hc-section-title">{{ $t('PATRA.AI_CARD.CONTEXT') }}</div>
      <div class="ai-hc-section-text">{{ attrs.customer_context }}</div>
    </div>

    <div v-if="attrs.ai_insight" class="ai-hc-section">
      <div class="ai-hc-section-title">{{ $t('PATRA.AI_CARD.INSIGHT') }}</div>
      <div class="ai-hc-section-text">{{ attrs.ai_insight }}</div>
    </div>

    <button class="ai-hc-ask-btn" @click="askPatraAi">
      {{ $t('PATRA.AI_CARD.ASK_PATRA') }}
    </button>
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
  /* A7: tokenized — hardcoded dark-theme hex broke light mode */
  color: var(--text, #1a1a24);
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

.ai-hc-section {
  margin-top: 6px;
  padding-top: 6px;
  border-top: 1px solid rgba(110, 86, 207, 0.12);
}

.ai-hc-section-title {
  font-size: 10px;
  font-weight: 600;
  color: #75727f;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  margin-bottom: 3px;
}

.ai-hc-section-text {
  font-size: 12px;
  color: var(--text, #1a1a24);
  line-height: 1.4;
}
</style>
