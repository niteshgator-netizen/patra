<script setup>
import { defineProps, defineModel, computed } from 'vue';
import { useToggle } from '@vueuse/core';

import Button from 'dashboard/components-next/button/Button.vue';
import WithLabel from './WithLabel.vue';

const props = defineProps({
  label: {
    type: String,
    required: true,
  },
  type: {
    type: String,
    default: 'text',
  },
  icon: {
    type: String,
    default: '',
  },
  name: {
    type: String,
    required: true,
  },
  hasError: Boolean,
  errorMessage: {
    type: String,
    default: '',
  },
  spacing: {
    type: String,
    default: 'base',
    validator: value => ['base', 'compact'].includes(value),
  },
  variant: {
    type: String,
    default: 'default',
    validator: value => ['default', 'patra'].includes(value),
  },
});

const FIELDS = {
  TEXT: 'text',
  PASSWORD: 'password',
};

defineOptions({
  inheritAttrs: false,
});

const model = defineModel({
  type: [String, Number],
  required: true,
});

const [isPasswordVisible, togglePasswordVisibility] = useToggle();

const isPasswordField = computed(() => props.type === FIELDS.PASSWORD);
const isPatra = computed(() => props.variant === 'patra');

const currentInputType = computed(() => {
  if (isPasswordField.value) {
    return isPasswordVisible.value ? FIELDS.TEXT : FIELDS.PASSWORD;
  }
  return props.type;
});

const inputClasses = computed(() =>
  isPatra.value
    ? 'peer block w-full bg-auth-input-bg border border-auth-border rounded-xl px-3.5 pt-[18px] pb-2 text-sm text-auth-text outline-none transition-all hover:border-auth-border-hi focus:border-patra focus:shadow-[0_0_0_4px_rgba(110,86,207,0.12)] appearance-none sm:leading-6'
    : 'block w-full border-none rounded-md shadow-sm bg-n-alpha-black2 appearance-none outline outline-1 focus:outline focus:outline-1 text-n-slate-12 placeholder:text-n-slate-10 sm:text-sm sm:leading-6 px-3 py-3'
);

const errorInputClasses = computed(() =>
  isPatra.value
    ? 'border-red-500/70 hover:border-red-400 focus:border-red-400 focus:shadow-[0_0_0_4px_rgba(239,68,68,0.12)]'
    : 'error outline-n-ruby-8 dark:outline-n-ruby-8 hover:outline-n-ruby-9 dark:hover:outline-n-ruby-9 disabled:outline-n-ruby-8 dark:disabled:outline-n-ruby-8'
);

const normalInputClasses = computed(
  () =>
    !isPatra.value &&
    !props.hasError &&
    'outline-n-weak dark:outline-n-weak hover:outline-n-slate-6 dark:hover:outline-n-slate-6 focus:outline-n-brand dark:focus:outline-n-brand'
);

const spacingClasses = computed(() => {
  if (isPatra.value) return '';
  return props.spacing === 'base' ? 'px-3 py-3' : 'px-3 py-2 mb-0';
});

const toggleButtonClasses = computed(() =>
  isPatra.value
    ? 'absolute inset-y-0 right-0 pr-3 text-auth-text-dim hover:text-auth-text'
    : 'absolute inset-y-0 right-0 pr-3'
);
</script>

<template>
  <WithLabel
    :label="label"
    :icon="icon"
    :name="name"
    :has-error="hasError"
    :error-message="errorMessage"
    :variant="variant"
  >
    <template #rightOfLabel>
      <slot />
    </template>
    <input
      v-bind="$attrs"
      v-model="model"
      :name="name"
      :type="currentInputType"
      :placeholder="isPatra ? ' ' : undefined"
      :aria-label="isPatra ? label : undefined"
      :class="[
        inputClasses,
        hasError ? errorInputClasses : normalInputClasses,
        spacingClasses,
        {
          'pl-9': icon,
          'pr-10': isPasswordField,
        },
      ]"
    />
    <Button
      v-if="isPasswordField"
      type="button"
      slate
      sm
      link
      :icon="isPasswordVisible ? 'i-lucide-eye-off' : 'i-lucide-eye'"
      :class="toggleButtonClasses"
      :aria-label="isPasswordVisible ? 'Hide password' : 'Show password'"
      :aria-pressed="isPasswordVisible"
      @click="togglePasswordVisibility()"
    />
  </WithLabel>
</template>
