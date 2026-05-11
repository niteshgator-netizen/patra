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
    <circle cx="50" cy="50" r="50" fill="#534AB7" />
    <text
      x="50"
      y="68"
      font-family="Arial,sans-serif"
      font-size="60"
      font-weight="700"
      fill="white"
      text-anchor="middle"
    >P</text>
  </svg>
</template>
