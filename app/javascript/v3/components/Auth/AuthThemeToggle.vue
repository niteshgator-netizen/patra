<script setup>
import { onMounted, ref } from 'vue';

const isDark = ref(true);

const applyTheme = dark => {
  isDark.value = dark;
  const theme = dark ? 'dark' : 'light';
  document.documentElement.setAttribute('data-theme', theme);
  document.documentElement.classList.toggle('dark', dark);
  localStorage.setItem('patra-theme', theme);
};

const toggleTheme = () => {
  applyTheme(!isDark.value);
};

onMounted(() => {
  const saved = localStorage.getItem('patra-theme');
  applyTheme(saved !== 'light');
});
</script>

<template>
  <button
    type="button"
    class="w-10 h-10 rounded-xl bg-patra-surface-2 border border-patra-border text-zinc-400 hover:text-white hover:border-patra-border-hi hover:bg-patra-surface-3 transition-all flex items-center justify-center"
    :aria-label="$t('PATRA_AUTH.THEME_TOGGLE_LABEL')"
    @click="toggleTheme"
  >
    <svg
      v-if="isDark"
      class="w-[18px] h-[18px]"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
    >
      <circle cx="12" cy="12" r="4" />
      <path
        d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"
      />
    </svg>
    <svg
      v-else
      class="w-[18px] h-[18px]"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
    >
      <path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z" />
    </svg>
  </button>
</template>
