<template>
  <div class="patra-pop-separator h-0 border-b border-n-strong -mx-2" />
</template>

<style scoped>
/* A7: dark values live under .dark only — bare-scope dark hex broke light mode */
.dark .patra-pop-separator {
  border-color: #171520 !important;
}

body:not(.dark) .patra-pop-separator {
  border-color: #e5e3eb !important;
}
</style>
