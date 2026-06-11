<script setup>
import { ref, computed, onMounted, onUnmounted, watch } from 'vue';
import { evaluateSLAStatus } from '@chatwoot/utils';

import Icon from 'dashboard/components-next/icon/Icon.vue';
import Label from 'dashboard/components-next/label/Label.vue';

const props = defineProps({
  chat: {
    type: Object,
    default: () => ({}),
  },
});

const REFRESH_INTERVAL = 60000;

const timer = ref(null);
const slaStatus = ref({
  threshold: null,
  isSlaMissed: false,
  type: null,
  icon: null,
});

defineOptions({
  inheritAttrs: false,
});

const appliedSLA = computed(() => props.chat?.applied_sla);
const hasSlaThreshold = computed(() => slaStatus.value?.threshold);
const isSlaMissed = computed(() => slaStatus.value?.isSlaMissed);

/* 4c: green → amber → red countdown. Green (teal) while more than half the
   first-response window remains, amber once past halfway or when we can't
   quantify (NRT/RT due states), ruby when missed. */
const slaColor = computed(() => {
  // Depend on the slaStatus OBJECT (replaced by the 60s refresh tick) — the
  // derived booleans don't change value as time passes, so without this the
  // computed would never re-evaluate and the amber stage would never show.
  const status = slaStatus.value;
  if (status?.isSlaMissed) return 'ruby';
  const frtSeconds = Number(
    appliedSLA.value?.sla_first_response_time_threshold
  );
  const createdAt = Number(props.chat?.created_at);
  if (frtSeconds > 0 && createdAt > 0 && !props.chat?.first_reply_created_at) {
    const elapsed = Date.now() / 1000 - createdAt;
    return elapsed < frtSeconds / 2 ? 'teal' : 'amber';
  }
  return 'amber';
});

const updateSlaStatus = () => {
  slaStatus.value = evaluateSLAStatus({
    appliedSla: appliedSLA.value || {},
    chat: props.chat,
  });
};

const createTimer = () => {
  timer.value = setTimeout(() => {
    updateSlaStatus();
    createTimer();
  }, REFRESH_INTERVAL);
};

onMounted(() => {
  updateSlaStatus();
  createTimer();
});

onUnmounted(() => {
  if (timer.value) {
    clearTimeout(timer.value);
  }
});

watch(() => props.chat, updateSlaStatus);

defineExpose({
  hasSlaThreshold,
});
</script>

<template>
  <div
    v-if="hasSlaThreshold"
    v-bind="$attrs"
    class="relative flex items-center cursor-pointer min-w-fit group"
  >
    <Label :label="slaStatus.threshold" :color="slaColor" compact>
      <template #icon>
        <Icon icon="i-lucide-flame" class="flex-shrink-0 size-3.5" />
      </template>
    </Label>
  </div>
  <template v-else />
</template>
