<script>
export default {
  props: {
    label: {
      type: String,
      default: '',
    },
    bg: {
      type: String,
      default: 'bg-patra-surface',
    },
  },
};
</script>

<template>
  <div
    class="flex items-center gap-3.5 my-5 text-zinc-500 font-mono text-[11px] tracking-[0.18em] uppercase"
  >
    <div
      class="flex-1 h-px bg-gradient-to-r from-transparent via-patra-border-hi to-transparent"
    />
    <span v-if="label" :class="bg">{{ label }}</span>
    <div
      class="flex-1 h-px bg-gradient-to-l from-transparent via-patra-border-hi to-transparent"
    />
  </div>
</template>
