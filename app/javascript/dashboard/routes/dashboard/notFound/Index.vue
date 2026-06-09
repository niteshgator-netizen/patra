<script setup>
import { computed } from 'vue';
import { useRoute } from 'vue-router';
import { frontendURL } from 'dashboard/helper/URLHelper';

const route = useRoute();

// Mirror the guard's working target (accounts/:accountId/dashboard) so the
// back link always resolves, regardless of which account the user is in.
const dashboardUrl = computed(() =>
  frontendURL(`accounts/${route.params.accountId}/dashboard`)
);
</script>

<template>
  <div
    class="flex flex-col items-center justify-center w-full h-full gap-3 px-6 text-center bg-n-background"
  >
    <span class="text-5xl font-semibold text-n-slate-11 tabular-nums">404</span>
    <h1 class="text-2xl font-semibold text-n-slate-12">Page not found</h1>
    <p class="max-w-sm text-sm text-n-slate-11">
      The page you're looking for doesn't exist or may have moved.
    </p>
    <router-link
      :to="dashboardUrl"
      class="inline-flex items-center gap-2 px-4 py-2 mt-2 text-sm font-medium text-white rounded-lg bg-n-brand hover:bg-n-brand/90"
    >
      <span class="i-lucide-arrow-left size-4" />
      Back to dashboard
    </router-link>
  </div>
</template>
