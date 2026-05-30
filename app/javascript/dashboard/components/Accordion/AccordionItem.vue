<script setup>
import { defineEmits } from 'vue';
import EmojiOrIcon from 'shared/components/EmojiOrIcon.vue';

defineProps({
  title: {
    type: String,
    default: '',
  },
  compact: {
    type: Boolean,
    default: false,
  },
  icon: {
    type: String,
    default: '',
  },
  emoji: {
    type: String,
    default: '',
  },
  isOpen: {
    type: Boolean,
    default: true,
  },
  patra: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['toggle']);

const onToggle = () => {
  emit('toggle');
};
</script>

<template>
  <div v-if="patra" class="acc" :data-open="isOpen ? '1' : '0'">
    <button type="button" class="acc-h drag-handle" @click.stop="onToggle">
      <span class="flex items-center gap-2 min-w-0">
        <slot name="title">
          {{ title }}
        </slot>
      </span>
      <div class="flex items-center gap-2 shrink-0">
        <slot name="button" />
        <svg
          class="chev"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          aria-hidden="true"
        >
          <path d="M6 9l6 6 6-6" />
        </svg>
      </div>
    </button>
    <div class="acc-body">
      <slot />
    </div>
  </div>
  <div v-else class="text-sm">
    <button
      class="flex items-center select-none w-full rounded-lg bg-n-slate-2 outline outline-1 outline-n-weak m-0 cursor-grab justify-between py-2 px-4 drag-handle"
      :class="{ 'rounded-bl-none rounded-br-none': isOpen }"
      @click.stop="onToggle"
    >
      <div class="flex justify-between">
        <EmojiOrIcon class="inline-block w-5" :icon="icon" :emoji="emoji" />
        <h5 class="text-n-slate-12 text-sm mb-0 py-0 pr-2 pl-0">
          {{ title }}
        </h5>
      </div>
      <div class="flex flex-row">
        <slot name="button" />
        <div class="flex justify-end w-3 text-n-blue-11 cursor-pointer">
          <fluent-icon v-if="isOpen" size="24" icon="subtract" type="solid" />
          <fluent-icon v-else size="24" icon="add" type="solid" />
        </div>
      </div>
    </button>
    <div
      v-if="isOpen"
      class="outline outline-1 outline-n-weak -mt-[-1px] border-t-0 rounded-br-lg rounded-bl-lg"
      :class="compact ? 'p-0' : 'px-2 py-4'"
    >
      <slot />
    </div>
  </div>
</template>
