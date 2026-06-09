<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import PatraReportsAPI from 'dashboard/api/patraReports';

const { t } = useI18n();
const agents = ref([]);
const period = ref('weekly');
const loading = ref(true);

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
  try {
    const { data } = await PatraReportsAPI.get();
    agents.value = data.agent_performance || [];
  } catch (error) {
    agents.value = [];
  } finally {
    loading.value = false;
  }
});
</script>

<template>
  <div class="flex flex-col gap-4 p-6">
    <header>
      <h1 class="text-2xl font-semibold text-n-slate-12">
        {{ $t('PATRA.LEADERBOARD.TITLE') }}
      </h1>
      <p class="text-sm text-n-slate-11">{{ $t('PATRA.LEADERBOARD.SUBTITLE') }}</p>
    </header>

    <section class="rounded-xl border border-n-weak bg-n-solid-1 p-4">
      <table class="w-full text-sm lb-table">
      <thead>
        <tr class="text-left text-n-slate-11">
          <th class="pb-2">{{ $t('PATRA.LEADERBOARD.RANK') }}</th>
          <th class="pb-2">{{ $t('PATRA.REPORTS.AGENT') }}</th>
          <th class="pb-2">{{ $t('PATRA.LEADERBOARD.RESOLVED') }}</th>
          <th class="pb-2">{{ $t('PATRA.LEADERBOARD.RESPONSE_TIME') }}</th>
        </tr>
      </thead>
      <tbody>
        <tr v-if="loading">
          <td colspan="4" class="py-6 text-center text-n-slate-11">…</td>
        </tr>
        <tr v-else-if="!sortedAgents.length">
          <td colspan="4" class="py-6 text-center text-n-slate-11">
            {{ $t('PATRA.LEADERBOARD.EMPTY') }}
          </td>
        </tr>
        <tr
          v-for="(agent, idx) in sortedAgents"
          v-else
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
    </section>
  </div>
</template>

<style scoped>
/* FIX 3: the tbody <td>s carry no explicit text color, so in light mode they
   inherited a dark-theme value (#EDEDF2). text-n-slate-12 resolves through
   --n-slate-12, which only gets a light value inside .pat-page-wrap /
   .pat-settings-section (patra-themes.css:2793 / :4025) — this bare route is in
   neither. Pin the table to the globally theme-aware --text token (light
   #1A1A24 / dark #EDEDF2). The thead keeps its own text-n-slate-11. */
.lb-table {
  color: var(--text, #EDEDF2);
}
</style>
