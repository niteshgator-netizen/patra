<script setup>
import { computed } from 'vue';

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

const { variant, orientation, inReplyTo, shouldGroupWithNext } =
  useMessageContext();
const { t } = useI18n();

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
    <slot />
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
</style>
