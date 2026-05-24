<script setup>
import { onMounted, onUnmounted, ref } from 'vue';
import PatraGameHealthAPI from 'dashboard/api/patraGameHealth';

const games = ref([]);
const summary = ref({ active: 0, total: 0 });
const loading = ref(true);
let timer = null;

async function fetchHealth() {
  try {
    const { data } = await PatraGameHealthAPI.get();
    games.value = data.games || [];
    summary.value = { active: data.active_count || 0, total: data.total_count || 0 };
  } finally {
    loading.value = false;
  }
}

function statusEmoji(status) {
  if (status === 'healthy') return '🟢';
  if (status === 'degraded') return '🟡';
  return '🔴';
}

onMounted(() => {
  fetchHealth();
  timer = setInterval(fetchHealth, 60_000);
});

onUnmounted(() => {
  if (timer) clearInterval(timer);
});
</script>

<template>
  <div class="rounded-xl border border-n-weak bg-n-solid-1 p-4">
    <div class="mb-3 flex items-center justify-between">
      <h2 class="text-sm font-semibold text-n-slate-12">
        {{ $t('GAME_HEALTH.TITLE') }}
      </h2>
      <span class="text-xs text-n-slate-11">
        {{ summary.active }}/{{ summary.total }}
        {{ summary.active === summary.total ? '🟢' : '⚠️' }}
      </span>
    </div>
    <p v-if="loading" class="text-sm text-n-slate-11">{{ $t('GAME_HEALTH.LOADING') }}</p>
    <ul v-else class="space-y-2 text-sm">
      <li
        v-for="game in games"
        :key="game.id"
        class="flex items-center justify-between border-t border-n-weak pt-2 first:border-0 first:pt-0"
      >
        <span class="text-n-slate-12">{{ game.name }}</span>
        <span class="text-xs text-n-slate-11">
          {{ statusEmoji(game.status) }} {{ game.status }}
          <span v-if="game.failure_count">({{ game.failure_count }} fails)</span>
        </span>
      </li>
    </ul>
  </div>
</template>
