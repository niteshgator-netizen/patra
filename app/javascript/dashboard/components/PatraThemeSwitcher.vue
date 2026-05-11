<script setup>
import { ref, onMounted } from 'vue';

const STORAGE_KEY = 'patra_theme';
const DEFAULT_THEME = 'dark';
const THEMES = ['dark', 'light', 'midnight', 'forest'];

const active = ref(DEFAULT_THEME);

const applyTheme = theme => {
  active.value = theme;
  document.documentElement.setAttribute('data-theme', theme);
  try {
    localStorage.setItem(STORAGE_KEY, theme);
  } catch (e) {
    // localStorage can throw in private mode / quota errors — non-fatal
  }
};

onMounted(() => {
  let saved = DEFAULT_THEME;
  try {
    saved = localStorage.getItem(STORAGE_KEY) || DEFAULT_THEME;
  } catch (e) {
    // ignore
  }
  if (!THEMES.includes(saved)) saved = DEFAULT_THEME;
  applyTheme(saved);
});
</script>

<template>
  <div
    class="inline-flex gap-1 p-1 rounded-full border bg-[var(--patra-bg2)] border-[var(--patra-border)]"
  >
    <button
      v-for="theme in THEMES"
      :key="theme"
      type="button"
      class="px-3 py-1 text-xs font-medium capitalize rounded-full transition-colors"
      :class="
        active === theme
          ? 'bg-[var(--patra-accent)] text-white'
          : 'bg-transparent text-[var(--patra-text2)] hover:bg-[var(--patra-bg3)] hover:text-[var(--patra-text1)]'
      "
      @click="applyTheme(theme)"
    >
      {{ theme }}
    </button>
  </div>
</template>
