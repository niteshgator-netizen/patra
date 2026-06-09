<script setup>
import { useAttrs } from 'vue';

const attrs = useAttrs();
// Runtime URL (not a static src) so Vite serves it from the Rails public root
// instead of trying to bundle it. Mirrors ShareModal.vue's '/brand-assets/...'.
const logoSrc = '/brand-assets/patra-logo-tile.png';
</script>

<template>
  <img
    v-bind="attrs"
    :src="logoSrc"
    alt="Patra"
    width="24"
    height="24"
    style="object-fit: contain"
  />
</template>
