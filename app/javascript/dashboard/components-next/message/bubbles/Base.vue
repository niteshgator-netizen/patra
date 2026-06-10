<script setup>
import { computed } from 'vue';
import { useRouter } from 'vue-router';

import MessageMeta from '../MessageMeta.vue';

import { emitter } from 'shared/helpers/mitt';
import { useMessageContext } from '../provider.js';
import { useI18n } from 'vue-i18n';

import MessageFormatter from 'shared/helpers/MessageFormatter.js';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { MESSAGE_VARIANTS, ORIENTATION } from '../constants';

const props = defineProps({
  hideMeta: { type: Boolean, default: false },
});

const {
  variant,
  orientation,
  inReplyTo,
  shouldGroupWithNext,
  contentType,
  additionalAttributes,
  conversationId,
} = useMessageContext();
const { t } = useI18n();
const router = useRouter();

const isHandoffMessage = computed(
  () =>
    contentType.value === 'ai_handoff' ||
    additionalAttributes.value?.ai_handoff
);

const varaintBaseMap = {
  [MESSAGE_VARIANTS.AGENT]: 'patra-conv-bubble--agent',
  [MESSAGE_VARIANTS.PRIVATE]: 'patra-conv-bubble--private',
  [MESSAGE_VARIANTS.USER]: 'patra-conv-bubble--user',
  [MESSAGE_VARIANTS.ACTIVITY]: 'patra-conv-bubble--activity',
  [MESSAGE_VARIANTS.BOT]: 'patra-conv-bubble--bot',
  [MESSAGE_VARIANTS.TEMPLATE]: 'patra-conv-bubble--bot',
  [MESSAGE_VARIANTS.ERROR]: 'patra-conv-bubble--error',
  [MESSAGE_VARIANTS.EMAIL]: 'patra-conv-bubble--email w-full',
  [MESSAGE_VARIANTS.UNSUPPORTED]: 'patra-conv-bubble--unsupported',
};

const orientationMap = {
  [ORIENTATION.LEFT]:
    'patra-conv-bubble--left left-bubble rounded-[15px] ltr:rounded-bl-[5px] rtl:rounded-br-[5px]',
  [ORIENTATION.RIGHT]:
    'patra-conv-bubble--right right-bubble rounded-[15px] ltr:rounded-br-[5px] rtl:rounded-bl-[5px]',
  [ORIENTATION.CENTER]: 'patra-conv-bubble--center rounded-md',
};

const flexOrientationClass = computed(() => {
  const map = {
    [ORIENTATION.LEFT]: 'justify-start',
    [ORIENTATION.RIGHT]: 'justify-end',
    [ORIENTATION.CENTER]: 'justify-center',
  };

  return map[orientation.value];
});

const messageClass = computed(() => {
  const classToApply = [varaintBaseMap[variant.value]];

  if (variant.value !== MESSAGE_VARIANTS.ACTIVITY) {
    classToApply.push(orientationMap[orientation.value]);
  } else {
    classToApply.push('rounded-lg');
  }

  classToApply.push('patra-conv-bubble');

  return classToApply;
});

const scrollToMessage = () => {
  emitter.emit(BUS_EVENTS.SCROLL_TO_MESSAGE, {
    messageId: inReplyTo.value.id,
  });
};

const shouldShowMeta = computed(
  () =>
    !props.hideMeta &&
    !shouldGroupWithNext.value &&
    variant.value !== MESSAGE_VARIANTS.ACTIVITY
);

const replyToPreview = computed(() => {
  if (!inReplyTo) return '';

  const { content, attachments } = inReplyTo.value;

  if (content) return new MessageFormatter(content).formattedMessage;
  if (attachments?.length) {
    const firstAttachment = attachments[0];
    const fileType = firstAttachment.fileType ?? firstAttachment.file_type;

    return t(`CHAT_LIST.ATTACHMENTS.${fileType}.CONTENT`);
  }

  return t('CONVERSATION.REPLY_MESSAGE_NOT_FOUND');
});
</script>

<template>
  <div
    class="text-sm"
    :class="[
      messageClass,
      {
        'max-w-lg': variant !== MESSAGE_VARIANTS.EMAIL,
      },
    ]"
  >
    <div
      v-if="inReplyTo"
      class="p-2 -mx-1 mb-2 rounded-lg cursor-pointer bg-n-alpha-black1"
      @click="scrollToMessage"
    >
      <div
        v-dompurify-html="replyToPreview"
        class="prose prose-bubble line-clamp-2"
      />
    </div>
    <p
      v-if="variant === MESSAGE_VARIANTS.PRIVATE"
      class="mb-1 text-[10px] font-semibold uppercase tracking-wide text-n-amber-11/80"
    >
      {{ t('PATRA.MESSAGE.INTERNAL_NOTE') }}
    </p>
    <!-- Patra AI handoff message -->
    <div v-if="isHandoffMessage" class="patra-thread-handoff">
      <div class="patra-th-header">
        <span class="patra-th-dot" />
        <span class="patra-th-title">{{ $t('PATRA.AI_CARD.HANDED_BY') }}</span>
      </div>
      <div class="patra-th-grid">
        <div
          v-if="additionalAttributes?.intent"
          class="patra-th-row"
        >
          <span class="patra-th-label">{{ $t('PATRA.AI_CARD.INTENT') }}</span>
          <span class="patra-th-value">{{ additionalAttributes.intent }}</span>
        </div>
        <div
          v-if="additionalAttributes?.confidence"
          class="patra-th-row"
        >
          <span class="patra-th-label">{{ $t('PATRA.AI_CARD.CONFIDENCE') }}</span>
          <span class="patra-th-value">{{
            Math.round(additionalAttributes.confidence * 100)
          }}%</span>
        </div>
        <div
          v-if="additionalAttributes?.reason"
          class="patra-th-row"
        >
          <span class="patra-th-label">{{ $t('PATRA.AI_CARD.REASON') }}</span>
          <span class="patra-th-value">{{ additionalAttributes.reason }}</span>
        </div>
      </div>
      <div class="patra-th-actions">
        <button
          class="patra-th-btn"
          @click="
            router.push({
              name: 'conversation_through_inbox',
              params: { conversation_id: conversationId },
            })
          "
        >
          {{ $t('PATRA.AI_CARD.VIEW_CONVERSATION') }}
        </button>
      </div>
    </div>
    <slot v-else />
    <!-- Message reactions area (placeholder for future feature) -->
    <div class="patra-reacts">
      <!-- Reactions will render here when implemented -->
    </div>
    <MessageMeta
      v-if="shouldShowMeta"
      :class="[
        flexOrientationClass,
        variant === MESSAGE_VARIANTS.EMAIL ? 'px-3 pb-3' : '',
      ]"
      class="patra-conv-msg-meta mt-2"
    />
  </div>
</template>

<style scoped>
.patra-conv-bubble {
  --pb-bubble-in: #131119;
  --pb-border: #171520;
  --pb-patra: #6e56cf;
  --pb-patra-2: #8b5cf6;
  --pb-patra-3: #a78bfa;
  --pb-patra-deep: #5b45b0;
  --pb-patra-glow: rgba(110, 86, 207, 0.55);
  --pb-text: #ededf2;
  --pb-text-3: #75727f;
  --pb-text-4: #54515e;
  --pb-amber: #e3a008;
  --pb-red: #f85149;

  padding: 11px 14px;
  font-size: 13.5px;
  line-height: 1.5;
  position: relative;
  transition: transform 0.15s;
}

.patra-conv-bubble:hover {
  transform: translateY(-1px);
}

/* A5: --pb-* tokens above are DARK values on the bare class — light values: */
body:not(.dark) .patra-conv-bubble {
  --pb-bubble-in: #f2f0f7;
  --pb-border: #e5e3eb;
  --pb-patra-glow: rgba(110, 86, 207, 0.28);
  --pb-text: #1a1a24;
  --pb-text-3: #75727f;
  --pb-text-4: #a0a0ab;
  --pb-amber: #9a6700;
  --pb-red: #cf222e;
}

.patra-conv-bubble--user {
  background: var(--pb-bubble-in);
  border: 1px solid var(--pb-border);
  color: var(--pb-text);
}

.patra-conv-bubble--agent,
.patra-conv-bubble--right.patra-conv-bubble--agent {
  background: linear-gradient(135deg, var(--pb-patra), var(--pb-patra-deep));
  color: #fff;
  border: none;
  box-shadow: 0 4px 16px var(--pb-patra-glow);
}

.patra-conv-bubble--bot {
  background: linear-gradient(
    135deg,
    rgba(110, 86, 207, 0.16),
    rgba(139, 92, 246, 0.07)
  );
  border: 1px solid rgba(139, 92, 246, 0.32);
  color: var(--pb-text);
}

.patra-conv-bubble--private {
  background: rgba(227, 160, 8, 0.12);
  border: 1px solid rgba(227, 160, 8, 0.28);
  color: var(--pb-amber);
}

.patra-conv-bubble--private :deep(.prosemirror-mention-node) {
  font-weight: 600;
}

.patra-conv-bubble--activity {
  background: transparent;
  border: none;
  color: var(--pb-text-4);
  font-size: 11px;
  padding: 2px 0;
}

.patra-conv-bubble--activity:hover {
  transform: none;
}

.patra-conv-bubble--activity,
.patra-conv-bubble--activity span,
:deep(.patra-conv-bubble--activity),
:deep(.patra-conv-bubble--activity span) {
  font-family: 'JetBrains Mono', ui-monospace, monospace !important;
}

.patra-conv-bubble--error {
  background: rgba(248, 81, 73, 0.12);
  border: 1px solid rgba(248, 81, 73, 0.35);
  color: var(--pb-red);
}

.patra-conv-bubble--unsupported {
  background: rgba(227, 160, 8, 0.1);
  border: 1px dashed rgba(227, 160, 8, 0.4);
  color: var(--pb-amber);
}

.patra-conv-bubble--email {
  background: var(--pb-bubble-in);
  border: 1px solid var(--pb-border);
  color: var(--pb-text);
  padding: 0;
}

.patra-conv-bubble--email:hover {
  transform: none;
}

.patra-thread-handoff {
  background: rgba(110, 86, 207, 0.06);
  border: 1px solid rgba(139, 92, 246, 0.25);
  border-radius: 14px;
  padding: 12px 14px;
  margin: 8px 0;
  max-width: 420px;
}

.patra-th-header {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-bottom: 8px;
}

.patra-th-dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: #f85149;
}

.patra-th-title {
  font-size: 12px;
  font-weight: 600;
  color: #a78bfa;
}

.patra-th-grid {
  display: grid;
  grid-template-columns: auto 1fr;
  gap: 4px 12px;
}

.patra-th-row {
  display: contents;
}

.patra-th-label {
  font-size: 11px;
  color: #75727f;
  font-weight: 600;
}

.patra-th-value {
  font-size: 11px;
  /* A7: tokenized — hardcoded dark-theme hex broke light mode */
  color: var(--text, #1a1a24);
}

.patra-th-actions {
  margin-top: 8px;
}

.patra-th-btn {
  padding: 5px 14px;
  border-radius: 8px;
  font-size: 11px;
  font-weight: 600;
  background: rgba(110, 86, 207, 0.12);
  color: #a78bfa;
  border: 1px solid rgba(110, 86, 207, 0.25);
  cursor: pointer;
}

.patra-reacts {
  display: flex;
  gap: 4px;
  margin-top: 2px;
  min-height: 0;
}

.patra-reacts:empty {
  display: none;
}
</style>
