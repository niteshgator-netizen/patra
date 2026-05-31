<script setup>
import { useRoute } from 'vue-router';

defineProps({
  keepAlive: {
    type: Boolean,
    default: true,
  },
});

const route = useRoute();
</script>

<template>
  <div
    class="pat-settings-shell flex flex-col w-full h-full m-0 pb-8 pt-4 px-6 overflow-auto"
  >
    <div class="flex items-start w-full max-w-5xl mx-auto">
      <router-view v-slot="{ Component }">
        <keep-alive v-if="keepAlive">
          <component :is="Component" :key="route.fullPath" />
        </keep-alive>
        <component :is="Component" v-else :key="route.fullPath" />
      </router-view>
    </div>
  </div>
</template>

<style scoped>
.pat-settings-shell {
  --canvas: #050409;
  --surface: #0c0b12;
  --border: #171520;
  --text: #ededf2;
  --text-2: #a8a6b6;
  background: var(--canvas) !important;
  color: var(--text);
}

.pat-settings-shell :deep(.bg-n-surface-1),
.pat-settings-shell :deep(.bg-n-solid-1) {
  background: var(--canvas) !important;
}

.pat-settings-shell :deep(.text-n-slate-12) {
  color: var(--text) !important;
}

.pat-settings-shell :deep(.text-n-slate-11) {
  color: var(--text-2) !important;
}

.pat-settings-shell :deep(.border-n-weak) {
  border-color: var(--border) !important;
}
</style>
