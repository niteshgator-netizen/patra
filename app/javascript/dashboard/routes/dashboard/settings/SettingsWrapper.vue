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
    class="pat-settings pat-settings-shell flex w-full h-full min-h-0 m-0"
  >
    <div class="pat-settings-body flex items-start w-full max-w-5xl mx-auto">
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

/* ── v6 settings ── */
.pat-settings {
  display: flex;
  height: 100%;
  min-height: 100%;
  background: var(--canvas, #050409);
}

.pat-settings-body {
  flex: 1;
  overflow-y: auto;
  padding: 28px 32px;
  min-height: 0;
}

.pat-settings-body :deep(.card) {
  background: var(--surface, #0c0b12);
  border: 1px solid var(--border, #171520);
  border-radius: 14px;
  padding: 22px 24px;
  margin-bottom: 20px;
}

.pat-settings-body :deep(.fld) {
  margin-bottom: 16px;
}

.pat-settings-body :deep(.fld label) {
  display: block;
  font-size: 12px;
  font-weight: 600;
  color: var(--text-2, #a8a6b6);
  margin-bottom: 6px;
  letter-spacing: 0.01em;
}

.pat-settings-body :deep(.fld input),
.pat-settings-body :deep(.fld textarea),
.pat-settings-body :deep(.fld select),
.pat-settings-body :deep(.fld .pat-input input),
.pat-settings-body :deep(.fld .pat-select) {
  width: 100%;
  background: var(--canvas, #050409);
  border: 1px solid var(--border, #171520);
  border-radius: 10px;
  padding: 9px 13px;
  color: var(--text, #ededf2);
  font-size: 13px;
  font-family: 'Inter', sans-serif;
  outline: none;
  transition: border-color 0.2s, box-shadow 0.2s;
}

.pat-settings-body :deep(.fld input:focus),
.pat-settings-body :deep(.fld textarea:focus),
.pat-settings-body :deep(.fld select:focus) {
  border-color: var(--patra, #6e56cf);
  box-shadow: 0 0 0 3px rgba(110, 86, 207, 0.13);
}

.pat-settings-body :deep(.btn.primary) {
  margin-top: 8px;
}
</style>
