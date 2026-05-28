<script setup>
import AuthThemeToggle from './AuthThemeToggle.vue';
</script>

<template>
  <div class="w-full max-w-[1280px] mx-auto px-6 sticky top-3 z-40 mt-3.5">
    <div
      class="h-[60px] flex items-center justify-between bg-patra-surface/60 backdrop-blur-md border border-patra-border rounded-2xl px-3 pl-5 pr-3"
    >
      <a
        href="/"
        class="flex items-center gap-2.5 font-display font-bold text-lg tracking-tight no-underline text-white"
      >
        <span
          class="w-7 h-7 rounded-lg bg-gradient-to-br from-patra to-patra-deep flex items-center justify-center font-display font-bold text-white text-base shadow-patra-glow"
        >
          {{ $t('PATRA_AUTH.BRAND_INITIAL') }}
        </span>
        {{ $t('PATRA_AUTH.BRAND_NAME') }}
        <span
          class="inline-flex items-center justify-center w-[18px] h-[18px] rounded ml-0.5 text-[9px] text-white bg-gradient-to-br from-patra-light to-patra shadow-patra-glow"
        >
          {{ $t('PATRA_AUTH.BRAND_DIAMOND') }}
        </span>
      </a>
      <AuthThemeToggle />
    </div>
  </div>
</template>
