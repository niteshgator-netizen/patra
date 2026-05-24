<script setup>
import { computed, onMounted, ref } from 'vue';
import { useAccount } from 'dashboard/composables/useAccount';

const { currentAccount } = useAccount();
const dismissed = ref(false);

const steps = computed(() => {
  const attrs = currentAccount.value?.custom_attributes || {};
  const onboarding = attrs.onboarding_checklist || {};
  return [
    { id: 'facebook', labelKey: 'ONBOARDING.FACEBOOK', done: onboarding.facebook },
    { id: 'game', labelKey: 'ONBOARDING.GAME', done: onboarding.game },
    { id: 'payment', labelKey: 'ONBOARDING.PAYMENT', done: onboarding.payment },
    { id: 'hours', labelKey: 'ONBOARDING.HOURS', done: onboarding.hours },
    { id: 'persona', labelKey: 'ONBOARDING.PERSONA', done: onboarding.persona },
    { id: 'test', labelKey: 'ONBOARDING.TEST', done: onboarding.test },
  ];
});

const allComplete = computed(() => steps.value.every(s => s.done));
const visible = computed(() => !dismissed.value && !allComplete.value);

onMounted(() => {
  dismissed.value = currentAccount.value?.custom_attributes?.onboarding_dismissed === true;
});

function dismiss() {
  dismissed.value = true;
}
</script>

<template>
  <div
    v-if="visible"
    class="rounded-xl border border-n-weak bg-n-solid-1 p-4"
  >
    <div class="mb-3 flex items-center justify-between">
      <h2 class="text-sm font-semibold text-n-slate-12">
        {{ $t('ONBOARDING.TITLE') }}
      </h2>
      <button type="button" class="text-xs text-n-slate-11" @click="dismiss">
        {{ $t('ONBOARDING.DISMISS') }}
      </button>
    </div>
    <ul class="space-y-2 text-sm">
      <li v-for="step in steps" :key="step.id" class="flex items-center gap-2">
        <span>{{ step.done ? '✅' : '⬜' }}</span>
        <span :class="step.done ? 'text-n-slate-11 line-through' : 'text-n-slate-12'">
          {{ $t(step.labelKey) }}
        </span>
      </li>
    </ul>
  </div>
</template>
