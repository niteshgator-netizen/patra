<script setup>
import { useAttrs } from 'vue';

const attrs = useAttrs();
</script>

<template>
  <svg
    v-bind="attrs"
    width="24"
    height="24"
    viewBox="0 0 100 100"
    xmlns="http://www.w3.org/2000/svg"
  >
    <defs>
      <linearGradient id="patraLogoGrad" x1="0%" y1="0%" x2="100%" y2="100%">
        <stop offset="0%" stop-color="#7D3DF5" />
        <stop offset="100%" stop-color="#5748ED" />
      </linearGradient>
    </defs>
    <rect x="0" y="0" width="100" height="100" rx="26" fill="url(#patraLogoGrad)" />
    <text x="50" y="51" font-family="Georgia, 'Times New Roman', serif" font-size="64" font-weight="700" fill="#FFFFFF" text-anchor="middle" dominant-baseline="central">P</text>
  </svg>
</template>
