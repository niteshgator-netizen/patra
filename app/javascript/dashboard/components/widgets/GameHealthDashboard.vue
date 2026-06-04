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
  <div class="pat-games">
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
    <ul v-else class="pat-game-grid">
      <li
        v-for="game in games"
        :key="game.id"
        class="pat-game-card flex items-center justify-between"
      >
        <span class="game-name">{{ game.name }}</span>
        <span
          class="pat-game-status text-xs"
          :class="{
            ok: game.status === 'healthy',
            warn: game.status === 'degraded',
            err: game.status !== 'healthy' && game.status !== 'degraded',
          }"
        >
          {{ statusEmoji(game.status) }} {{ game.status }}
          <span v-if="game.failure_count">({{ game.failure_count }} fails)</span>
        </span>
      </li>
    </ul>
  </div>
</template>

<style scoped>
/* ── v6 games panel ── */
.pat-games {
  background: var(--canvas, #050409);
  padding: 20px;
}
.pat-game-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(260px, 1fr));
  gap: 14px;
}
.pat-game-grid .pat-game-card {
  flex-direction: row;
  align-items: center;
  justify-content: space-between;
}

.pat-game-card {
  background: var(--surface, #0c0b12);
  border: 1px solid var(--border, #171520);
  border-radius: 14px;
  padding: 16px;
  display: flex;
  flex-direction: column;
  gap: 10px;
  transition:
    border-color 0.2s,
    box-shadow 0.2s;
  position: relative;
  overflow: hidden;
}
.pat-game-card:hover {
  border-color: var(--patra, #6e56cf);
  box-shadow:
    0 0 0 1px rgba(110, 86, 207, 0.2),
    0 8px 24px -8px var(--patra-glow, rgba(110, 86, 207, 0.4));
}
.pat-game-card .game-name {
  font-family: 'Space Grotesk', sans-serif;
  font-size: 15px;
  font-weight: 600;
  color: var(--text, #ededf2);
}
.pat-game-status {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  font-size: 11px;
  font-weight: 600;
  padding: 3px 9px;
  border-radius: 20px;
}
.pat-game-status.ok {
  background: rgba(63, 185, 80, 0.14);
  color: var(--green, #3fb950);
}
.pat-game-status.warn {
  background: rgba(227, 160, 8, 0.14);
  color: var(--amber, #e3a008);
}
.pat-game-status.err {
  background: rgba(248, 81, 73, 0.14);
  color: var(--red, #f85149);
}
.pat-game-action {
  height: 30px;
  padding: 0 14px;
  border-radius: 8px;
  background: var(--surface-3, #1b1925);
  border: 1px solid var(--border-hi, #2e2940);
  color: var(--text-2, #a8a6b6);
  font-size: 12px;
  font-weight: 500;
  cursor: pointer;
  transition: all 0.2s;
  font-family: Inter, sans-serif;
  display: inline-flex;
  align-items: center;
  gap: 6px;
}
.pat-game-action:hover {
  background: var(--surface-4, #252233);
  color: var(--text, #ededf2);
  transform: translateY(-1px);
}
.pat-game-action.primary {
  background: linear-gradient(
    135deg,
    var(--patra, #6e56cf),
    var(--patra-deep, #5b45b0)
  );
  color: #fff;
  border-color: transparent;
  box-shadow: 0 3px 10px var(--patra-glow, rgba(110, 86, 207, 0.4));
}
.pat-balance {
  font-family: 'JetBrains Mono', monospace;
  font-size: 18px;
  font-weight: 700;
  color: var(--green, #3fb950);
}
</style>
