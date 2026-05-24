<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  chatId: { type: [Number, String], required: true },
  hasUnread: { type: Boolean, default: false },
});

const emit = defineEmits(['mark-read', 'resolve', 'click']);

const { t } = useI18n();
const offsetX = ref(0);
const startX = ref(0);
const swiping = ref(false);
const SWIPE_THRESHOLD = 72;
const MAX_SWIPE = 120;

const onTouchStart = e => {
  startX.value = e.touches[0].clientX;
  swiping.value = true;
};

const onTouchMove = e => {
  if (!swiping.value) return;
  const delta = e.touches[0].clientX - startX.value;
  if (delta < 0) {
    offsetX.value = Math.max(delta, -MAX_SWIPE);
  } else if (offsetX.value < 0) {
    offsetX.value = Math.min(0, offsetX.value + delta);
  }
};

const resetSwipe = () => {
  offsetX.value = 0;
  swiping.value = false;
};

const onTouchEnd = () => {
  if (offsetX.value <= -SWIPE_THRESHOLD) {
    offsetX.value = -MAX_SWIPE;
  } else {
    resetSwipe();
  }
  swiping.value = false;
};

const onMarkRead = () => {
  emit('mark-read', props.chatId);
  resetSwipe();
};

const onResolve = () => {
  emit('resolve', props.chatId);
  resetSwipe();
};
</script>

<template>
  <div class="relative overflow-hidden md:overflow-visible">
    <div
      class="absolute inset-y-0 right-0 flex items-stretch"
      :class="offsetX < -20 ? 'opacity-100' : 'opacity-0 pointer-events-none'"
    >
      <button
        v-if="hasUnread"
        type="button"
        class="flex items-center px-3 text-xs font-medium text-white bg-n-brand"
        @click.stop="onMarkRead"
      >
        {{ t('PATRA.SWIPE.MARK_READ') }}
      </button>
      <button
        type="button"
        class="flex items-center px-3 text-xs font-medium text-white bg-n-teal-9"
        @click.stop="onResolve"
      >
        {{ t('PATRA.SWIPE.RESOLVE') }}
      </button>
    </div>
    <div
      class="relative bg-n-background transition-transform duration-150 ease-out md:translate-x-0"
      :style="{ transform: `translateX(${offsetX}px)` }"
      @touchstart.passive="onTouchStart"
      @touchmove.passive="onTouchMove"
      @touchend="onTouchEnd"
      @touchcancel="onTouchEnd"
      @click="emit('click', $event)"
    >
      <slot />
    </div>
  </div>
</template>
