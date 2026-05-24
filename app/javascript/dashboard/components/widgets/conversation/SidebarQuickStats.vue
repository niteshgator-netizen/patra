<script setup>
import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
const stats = useMapGetter('conversationStats/getStats');

const items = computed(() => [
  { label: t('PATRA.SIDEBAR.OPEN'), count: stats.value.allCount },
  { label: t('PATRA.SIDEBAR.MINE'), count: stats.value.mineCount },
  { label: t('PATRA.SIDEBAR.UNASSIGNED'), count: stats.value.unAssignedCount },
]);
</script>

<template>
  <div class="grid grid-cols-3 gap-1 px-2 py-2 border-b border-n-weak">
    <div
      v-for="item in items"
      :key="item.label"
      class="rounded-lg border border-n-weak bg-n-alpha-1 px-2 py-1.5 text-center"
    >
      <p class="text-lg font-semibold tabular-nums text-n-slate-12">
        {{ item.count }}
      </p>
      <p class="text-[10px] font-medium uppercase tracking-wide text-n-slate-11">
        {{ item.label }}
      </p>
    </div>
  </div>
</template>
