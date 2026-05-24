<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import PatraReportsAPI from 'dashboard/api/patraReports';

const { t } = useI18n();
const agents = ref([]);
const period = ref('weekly');

const sortedAgents = computed(() =>
  [...agents.value].sort((a, b) => (b.resolved || 0) - (a.resolved || 0))
);

const badgeFor = index => {
  if (index === 0) return '🥇';
  if (index === 1) return '🥈';
  if (index === 2) return '🥉';
  return '';
};

onMounted(async () => {
  const { data } = await PatraReportsAPI.get();
  agents.value = data.agent_performance || [];
});
</script>

<template>
  <div class="flex flex-col gap-4 p-6">
    <header>
      <h1 class="text-2xl font-semibold">{{ $t('PATRA.LEADERBOARD.TITLE') }}</h1>
      <p class="text-sm text-n-slate-11">{{ $t('PATRA.LEADERBOARD.SUBTITLE') }}</p>
    </header>

    <table class="w-full text-sm">
      <thead>
        <tr class="text-left text-n-slate-11">
          <th class="pb-2">{{ $t('PATRA.LEADERBOARD.RANK') }}</th>
          <th class="pb-2">{{ $t('PATRA.REPORTS.AGENT') }}</th>
          <th class="pb-2">{{ $t('PATRA.LEADERBOARD.RESOLVED') }}</th>
          <th class="pb-2">{{ $t('PATRA.LEADERBOARD.RESPONSE_TIME') }}</th>
        </tr>
      </thead>
      <tbody>
        <tr
          v-for="(agent, idx) in sortedAgents"
          :key="agent.name"
          class="border-t border-n-weak"
        >
          <td class="py-2">{{ badgeFor(idx) }} {{ idx + 1 }}</td>
          <td class="py-2">{{ agent.name }}</td>
          <td class="py-2">{{ agent.resolved || agent.messages_today || 0 }}</td>
          <td class="py-2">{{ agent.avg_response_time || '—' }}</td>
        </tr>
      </tbody>
    </table>
  </div>
</template>
