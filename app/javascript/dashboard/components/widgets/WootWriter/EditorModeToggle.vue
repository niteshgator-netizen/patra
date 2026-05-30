<script setup>
import { computed, useTemplateRef } from 'vue';
import { useElementSize } from '@vueuse/core';
import { REPLY_EDITOR_MODES } from './constants';

const props = defineProps({
  mode: {
    type: String,
    default: REPLY_EDITOR_MODES.REPLY,
  },
  disabled: {
    type: Boolean,
    default: false,
  },
  isReplyRestricted: {
    type: Boolean,
    default: false,
  },
});

defineEmits(['toggleMode']);

const wootEditorReplyMode = useTemplateRef('wootEditorReplyMode');
const wootEditorPrivateMode = useTemplateRef('wootEditorPrivateMode');

const replyModeSize = useElementSize(wootEditorReplyMode);
const privateModeSize = useElementSize(wootEditorPrivateMode);

/**
 * Computed boolean indicating if the editor is in private note mode
 * When isReplyRestricted is true, force switch to private note
 * Otherwise, respect the current mode prop
 * @type {ComputedRef<boolean>}
 */
const isPrivate = computed(() => {
  if (props.isReplyRestricted) {
    // Force switch to private note when replies are restricted
    return true;
  }
  // Otherwise respect the current mode
  return props.mode === REPLY_EDITOR_MODES.NOTE;
});

/**
 * Computes the width of the sliding background chip in pixels
 * Includes 16px of padding in the calculation
 * @type {ComputedRef<string>}
 */
const width = computed(() => {
  const widthToUse = isPrivate.value
    ? privateModeSize.width.value
    : replyModeSize.width.value;

  const widthWithPadding = widthToUse + 16;
  return `${widthWithPadding}px`;
});

/**
 * Computes the X translation value for the sliding background chip
 * Translates by the width of reply mode + padding when in private mode
 * @type {ComputedRef<string>}
 */
const translateValue = computed(() => {
  const xTranslate = isPrivate.value ? replyModeSize.width.value + 16 : 0;

  return `${xTranslate}px`;
});
</script>

<template>
  <button
    class="patra-composer-tabs flex items-center w-auto h-8 p-1 transition-all relative duration-300 ease-in-out z-0 active:scale-[0.995] active:duration-75"
    :disabled="disabled || isReplyRestricted"
    :class="{
      'cursor-not-allowed': disabled || isReplyRestricted,
    }"
    @click="$emit('toggleMode')"
  >
    <div
      ref="wootEditorReplyMode"
      class="patra-composer-tab flex items-center gap-1 px-3 z-20"
      :class="{ 'is-active': !isPrivate }"
    >
      {{ $t('CONVERSATION.REPLYBOX.REPLY') }}
    </div>
    <div
      ref="wootEditorPrivateMode"
      class="patra-composer-tab flex items-center gap-1 px-3 z-20"
      :class="{ 'is-active': isPrivate, 'is-note': isPrivate }"
    >
      {{ $t('CONVERSATION.REPLYBOX.PRIVATE_NOTE') }}
    </div>
    <div
      class="patra-composer-tab-chip absolute shadow-sm rounded-lg h-6 w-[var(--chip-width)] ease-in-out translate-x-[var(--translate-x)] rtl:translate-x-[var(--rtl-translate-x)]"
      :class="{
        'transition-all duration-300': !disabled && !isReplyRestricted,
      }"
      :style="{
        '--chip-width': width,
        '--translate-x': translateValue,
        '--rtl-translate-x': `calc(-1 * var(--translate-x))`,
      }"
    />
  </button>
</template>

<style scoped>
.patra-composer-tabs {
  --pt-surface-2: #131119;
  --pt-text-3: #75727f;
  --pt-text: #ededf2;
  --pt-amber: #e3a008;
  --pt-border: #171520;

  gap: 4px;
  border: 1px solid transparent;
  border-color: #171520 !important;
  border-radius: 0;
  background: transparent;
}

.patra-composer-tab {
  font-size: 12px;
  font-weight: 500;
  padding: 5px 12px;
  border-radius: 8px;
  color: var(--pt-text-3);
  cursor: pointer;
  transition: all 0.2s;
  white-space: nowrap;
  border: 1px solid transparent;
  border-color: transparent !important;
}

.patra-composer-tab.is-active {
  color: var(--pt-text);
  background: var(--pt-surface-2);
  border-color: #6e56cf !important;
}

.patra-composer-tab.is-note.is-active {
  background: rgba(227, 160, 8, 0.15);
  color: var(--pt-amber);
  border-color: #171520 !important;
}

.patra-composer-tab-chip {
  display: none;
  border: 1px solid transparent;
  border-color: #171520 !important;
}
</style>
