<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import axios from 'axios';

const { t } = useI18n();
const stats = ref(null);
const loading = ref(true);

const healthClass = computed(() => {
  const depth = stats.value?.sidekiq_queue_depth || 0;
  if (depth > 1000) return 'text-n-ruby-11';
  if (depth > 100) return 'text-n-amber-11';
  return 'text-n-teal-11';
});

onMounted(async () => {
  try {
    const { data } = await axios.get('/super_admin/patra_dashboard');
    stats.value = data;
  } finally {
    loading.value = false;
  }
});
</script>

<template>
  <div class="flex flex-col gap-6 p-6">
    <h1 class="text-2xl font-semibold">{{ $t('PATRA.SUPER_ADMIN.TITLE') }}</h1>

    <div v-if="loading" class="text-n-slate-11">{{ $t('PATRA.SUPER_ADMIN.LOADING') }}</div>

    <div v-else-if="stats" class="grid grid-cols-2 gap-4 md:grid-cols-4">
      <div class="p-4 border rounded-xl border-n-weak">
        <p class="text-xs uppercase text-n-slate-11">{{ $t('PATRA.SUPER_ADMIN.ACCOUNTS') }}</p>
        <p class="text-2xl font-semibold">{{ stats.total_accounts }}</p>
      </div>
      <div class="p-4 border rounded-xl border-n-weak">
        <p class="text-xs uppercase text-n-slate-11">{{ $t('PATRA.SUPER_ADMIN.CONVERSATIONS') }}</p>
        <p class="text-2xl font-semibold">{{ stats.total_conversations }}</p>
      </div>
      <div class="p-4 border rounded-xl border-n-weak">
        <p class="text-xs uppercase text-n-slate-11">{{ $t('PATRA.SUPER_ADMIN.MESSAGES') }}</p>
        <p class="text-2xl font-semibold">{{ stats.total_messages }}</p>
      </div>
      <div class="p-4 border rounded-xl border-n-weak">
        <p class="text-xs uppercase text-n-slate-11">{{ $t('PATRA.SUPER_ADMIN.SIDEKIQ') }}</p>
        <p class="text-2xl font-semibold" :class="healthClass">{{ stats.sidekiq_queue_depth }}</p>
      </div>
    </div>
  </div>
</template>
