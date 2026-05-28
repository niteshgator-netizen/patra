<script setup>
import { computed } from 'vue';

const props = defineProps({
  label: { type: String, default: '' },
  name: { type: String, required: true },
  icon: { type: String, default: '' },
  hasError: { type: Boolean, default: false },
  helpMessage: { type: String, default: '' },
  errorMessage: { type: String, default: '' },
  variant: {
    type: String,
    default: 'default',
    validator: value => ['default', 'patra'].includes(value),
  },
});

const isPatra = computed(() => props.variant === 'patra');
</script>

<template>
  <div :class="isPatra ? 'space-y-1.5' : 'space-y-1'">
    <label
      v-if="label && !isPatra"
      :for="name"
      class="flex justify-between text-sm font-medium leading-6 text-n-slate-12"
      :class="{ 'text-n-ruby-12': hasError }"
    >
      <slot name="label">
        {{ label }}
      </slot>
      <slot name="rightOfLabel" />
    </label>
    <div class="w-full">
      <div
        class="relative flex items-center w-full"
        :class="{ 'flex items-center relative w-full': !isPatra }"
      >
        <fluent-icon
          v-if="icon"
          size="16"
          :icon="icon"
          :class="
            isPatra
              ? 'absolute left-3 z-10 text-zinc-500 w-5 h-5'
              : 'absolute left-2 transform text-n-slate-9 w-5 h-5'
          "
        />
        <slot />
        <label
          v-if="label && isPatra"
          :for="name"
          class="absolute left-3.5 top-1/2 -translate-y-1/2 text-sm text-zinc-500 font-mono uppercase tracking-wide pointer-events-none transition-all duration-200 peer-focus:top-2.5 peer-focus:translate-y-0 peer-focus:text-[10px] peer-focus:text-patra-light peer-[:not(:placeholder-shown)]:top-2.5 peer-[:not(:placeholder-shown)]:translate-y-0 peer-[:not(:placeholder-shown)]:text-[10px] peer-[:not(:placeholder-shown)]:text-patra-light"
          :class="{
            'left-9': icon,
            'text-red-400 peer-focus:text-red-400': hasError,
          }"
        >
          <slot name="label">
            {{ label }}
          </slot>
        </label>
      </div>
      <div v-if="isPatra && $slots.rightOfLabel" class="flex justify-end">
        <slot name="rightOfLabel" />
      </div>
      <div
        v-if="errorMessage && hasError"
        class="text-sm mt-1.5 ml-px leading-tight"
        :class="isPatra ? 'text-red-400' : 'text-n-ruby-9'"
      >
        {{ errorMessage }}
      </div>
      <div
        v-else-if="helpMessage || $slots.help"
        class="text-sm mt-1.5 ml-px leading-tight"
        :class="isPatra ? 'text-zinc-500' : 'text-n-slate-10'"
      >
        <slot name="help">
          {{ helpMessage }}
        </slot>
      </div>
    </div>
  </div>
</template>
