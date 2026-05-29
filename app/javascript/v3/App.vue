<script>
import SnackbarContainer from './components/SnackBar/Container.vue';

export default {
  components: { SnackbarContainer },
  data() {
    return { theme: 'light' };
  },
  mounted() {
    this.setColorTheme();
    this.listenToThemeChanges();
    this.setLocale(window.chatwootConfig.selectedLocale);
  },
  methods: {
    applyPatraTheme(theme) {
      const isDark = theme === 'dark';
      this.theme = theme;
      document.documentElement.setAttribute('data-theme', theme);
      document.documentElement.classList.toggle('dark', isDark);
    },
    setColorTheme() {
      const saved = localStorage.getItem('patra-theme');
      if (saved === 'light' || saved === 'dark') {
        this.applyPatraTheme(saved);
        return;
      }
      const prefersDark = window.matchMedia(
        '(prefers-color-scheme: dark)'
      ).matches;
      this.applyPatraTheme(prefersDark ? 'dark' : 'light');
    },
    listenToThemeChanges() {
      const mql = window.matchMedia('(prefers-color-scheme: dark)');

      mql.onchange = e => {
        if (localStorage.getItem('patra-theme')) return;
        this.applyPatraTheme(e.matches ? 'dark' : 'light');
      };
    },
    setLocale(locale) {
      if (locale) {
        this.$root.$i18n.locale = locale;
      }
    },
  },
};
</script>

<template>
  <div class="h-full min-h-screen w-full antialiased" :class="theme">
    <router-view />
    <SnackbarContainer />
  </div>
</template>

<style lang="scss">
@import url('https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@400;500;600;700&family=Inter:wght@400;500;600&family=JetBrains+Mono:wght@400;500&display=swap');

@tailwind base;
@tailwind components;
@tailwind utilities;

@import '../dashboard/assets/scss/next-colors';

:root[data-theme='dark'],
:root:not([data-theme]) {
  --auth-canvas: #0b0a0f;
  --auth-surface: #13121a;
  --auth-surface-2: #1a1926;
  --auth-surface-3: #232133;
  --auth-border: #1e1b29;
  --auth-border-hi: #3b3554;
  --auth-text: #ffffff;
  --auth-text-dim: #a1a1aa;
  --auth-text-mute: #71717a;
  --auth-input-bg: rgba(11, 10, 15, 0.6);
  --auth-card-bg: rgba(19, 18, 26, 0.55);
  --auth-nav-bg: rgba(19, 18, 26, 0.6);
  --auth-grid-line: rgba(255, 255, 255, 0.03);
  --auth-mesh-1: rgba(110, 86, 207, 0.22);
  --auth-mesh-2: rgba(139, 92, 246, 0.14);
  --auth-inset: rgba(255, 255, 255, 0.05);
}

:root[data-theme='light'] {
  --auth-canvas: #fafafb;
  --auth-surface: #ffffff;
  --auth-surface-2: #f4f3f7;
  --auth-surface-3: #ebe9f2;
  --auth-border: #e6e4ee;
  --auth-border-hi: #d2cee2;
  --auth-text: #16151c;
  --auth-text-dim: #5a5870;
  --auth-text-mute: #86849a;
  --auth-input-bg: rgba(255, 255, 255, 0.7);
  --auth-card-bg: rgba(255, 255, 255, 0.7);
  --auth-nav-bg: rgba(255, 255, 255, 0.7);
  --auth-grid-line: rgba(20, 18, 30, 0.04);
  --auth-mesh-1: rgba(110, 86, 207, 0.14);
  --auth-mesh-2: rgba(139, 92, 246, 0.09);
  --auth-inset: rgba(255, 255, 255, 0.6);
}

.auth-grid {
  background-image:
    linear-gradient(to right, var(--auth-grid-line) 1px, transparent 1px),
    linear-gradient(to bottom, var(--auth-grid-line) 1px, transparent 1px);
  background-size: 40px 40px;
}

.auth-mesh {
  background:
    radial-gradient(circle at 30% 30%, var(--auth-mesh-1), transparent 55%),
    radial-gradient(circle at 70% 60%, var(--auth-mesh-2), transparent 55%);
}

@media (max-width: 900px) {
  .auth-mesh {
    width: 600px !important;
    height: 400px !important;
    filter: blur(50px) !important;
    animation: none !important;
    opacity: 0.5 !important;
  }

  .auth-nav-blur {
    backdrop-filter: blur(8px) !important;
  }
}

@media (max-width: 480px) {
  .auth-mesh {
    filter: blur(40px) !important;
    opacity: 0.4 !important;
  }
}

@media (prefers-reduced-motion: reduce) {
  .auth-mesh,
  .auth-pulse,
  .auth-card-anim {
    animation: none !important;
  }
}

html,
body {
  font-family: 'Inter', system-ui, sans-serif;
  @apply h-full w-full;

  input,
  select {
    outline: none;
  }
}

.text-link {
  @apply text-patra-light font-medium hover:text-auth-text transition-colors;
}

.v-popper--theme-tooltip .v-popper__inner {
  background: black !important;
  font-size: 0.75rem;
  padding: 4px 8px !important;
  border-radius: 6px;
  font-weight: 400;
}

.v-popper--theme-tooltip .v-popper__arrow-container {
  display: none;
}
</style>
