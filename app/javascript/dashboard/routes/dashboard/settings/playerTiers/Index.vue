<template>
  <div class="flex-1 overflow-auto p-6">
    <div class="max-w-3xl">
      <h2 class="text-lg font-medium mb-4">Player Tiers</h2>
      <p class="text-sm text-slate-400 mb-6">Define player tiers with different rules and limits.</p>

      <div v-if="loading" class="text-sm text-slate-400">Loading...</div>

      <div v-else class="space-y-3">
        <div
          v-for="tier in tiers"
          :key="tier.id"
          class="flex items-center gap-4 p-4 border border-slate-700 rounded-lg"
        >
          <span
            class="w-3 h-3 rounded-full"
            :style="{ backgroundColor: tier.color }"
          />
          <div class="flex-1">
            <div class="font-medium text-sm">{{ tier.badge_text || tier.name }}</div>
            <div class="text-xs text-slate-400">{{ tier.name }}</div>
          </div>
          <span class="text-xs text-slate-500">
            {{ Object.keys(tier.rule_overrides || {}).length }} overrides
          </span>
        </div>
      </div>

      <p class="text-xs text-slate-500 mt-4">Tier overrides and editing coming in next update. Tiers are currently managed via contacts page.</p>
    </div>
  </div>
</template>

<script>
import PlayerTiersAPI from '../../../../api/playerTiers';

export default {
  data() {
    return { tiers: [], loading: true };
  },
  mounted() {
    this.fetchTiers();
  },
  methods: {
    async fetchTiers() {
      try {
        const accountId = this.$route.params.accountId;
        const { data } = await PlayerTiersAPI.getPlayerTiers(accountId);
        this.tiers = data;
      } catch (e) {
        console.error('Failed to fetch tiers:', e);
      } finally {
        this.loading = false;
      }
    },
  },
};
</script>
