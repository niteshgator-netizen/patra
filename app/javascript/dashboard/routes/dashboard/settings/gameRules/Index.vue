<script>
import GameRulesAPI from '../../../../api/gameRules';
import { useAlert } from 'dashboard/composables';

export default {
  data() {
    return {
      gameRules: [],
      loading: true,
      expanded: null,
    };
  },
  mounted() {
    this.fetchRules();
  },
  methods: {
    async fetchRules() {
      try {
        const accountId = this.$route.params.accountId;
        const { data } = await GameRulesAPI.getGameRules(accountId);
        this.gameRules = data;
      } catch (e) {
        console.error('Failed to fetch game rules:', e);
      } finally {
        this.loading = false;
      }
    },
    toggleExpand(gameId) {
      this.expanded = this.expanded === gameId ? null : gameId;
    },
    async saveRule(rule) {
      try {
        const accountId = this.$route.params.accountId;
        await GameRulesAPI.updateGameRule(accountId, rule.game_id, rule);
        useAlert('Game rules saved');
      } catch (e) {
        useAlert('Failed to save rules');
        console.error(e);
      }
    },
  },
};
</script>

<template>
  <div class="pat-tpage flex-1 overflow-auto p-6">
    <div class="max-w-4xl">
      <h2 class="text-lg font-medium mb-4">Game Rules</h2>
      <p class="text-sm text-slate-400 mb-6">
        Configure freeplay, deposit bonuses, and cashout rules per game.
      </p>

      <div v-if="loading" class="flex flex-col gap-3">
        <div v-for="n in 4" :key="n" class="pat-skel h-10 w-full" />
      </div>

      <div v-else class="space-y-4">
        <p
          v-if="!gameRules.length"
          class="text-sm text-slate-400 py-8 text-center"
        >
          No games configured yet. Connect a game integration to set freeplay,
          deposit, and cashout rules.
        </p>
        <div
          v-for="rule in gameRules"
          :key="rule.id || rule.game_id"
          class="border border-slate-700 rounded-lg"
        >
          <button
            class="w-full flex items-center justify-between p-4 text-left"
            @click="toggleExpand(rule.game_id)"
          >
            <span class="font-medium">{{
              rule.game?.name || rule.game?.slug || 'Game ' + rule.game_id
            }}</span>
            <span class="text-xs text-slate-400">{{
              expanded === rule.game_id ? '▲' : '▼'
            }}</span>
          </button>

          <div
            v-if="expanded === rule.game_id"
            class="p-4 border-t border-slate-700 space-y-6"
          >
            <!-- Freeplay Section -->
            <div>
              <h3 class="text-sm font-medium mb-3">Freeplay Rules</h3>
              <div class="grid grid-cols-2 gap-4">
                <label class="flex items-center gap-2">
                  <input v-model="rule.freeplay_enabled" type="checkbox" />
                  <span class="text-sm">Freeplay enabled</span>
                </label>
                <label class="block">
                  <span class="text-xs text-slate-400">Amount ($)</span>
                  <input
                    v-model.number="rule.freeplay_amount"
                    type="number"
                    class="w-full mt-1 p-2 bg-slate-800 border border-slate-600 rounded text-sm"
                  />
                </label>
                <label class="block">
                  <span class="text-xs text-slate-400">Max per day</span>
                  <input
                    v-model.number="rule.freeplay_max_per_day"
                    type="number"
                    class="w-full mt-1 p-2 bg-slate-800 border border-slate-600 rounded text-sm"
                  />
                </label>
                <label class="block">
                  <span class="text-xs text-slate-400">Max per week</span>
                  <input
                    v-model.number="rule.freeplay_max_per_week"
                    type="number"
                    class="w-full mt-1 p-2 bg-slate-800 border border-slate-600 rounded text-sm"
                  />
                </label>
                <label class="flex items-center gap-2">
                  <input
                    v-model="rule.freeplay_require_deposit_first"
                    type="checkbox"
                  />
                  <span class="text-sm">Require deposit first</span>
                </label>
                <label class="block">
                  <span class="text-xs text-slate-400">Freeplay message</span>
                  <input
                    v-model="rule.freeplay_message"
                    type="text"
                    class="w-full mt-1 p-2 bg-slate-800 border border-slate-600 rounded text-sm"
                  />
                </label>
              </div>
            </div>

            <!-- Deposit Bonus Section -->
            <div>
              <h3 class="text-sm font-medium mb-3">Deposit Bonus</h3>
              <div class="grid grid-cols-2 gap-4">
                <label class="flex items-center gap-2">
                  <input v-model="rule.deposit_bonus_enabled" type="checkbox" />
                  <span class="text-sm">Bonus enabled</span>
                </label>
                <label class="block">
                  <span class="text-xs text-slate-400">Bonus %</span>
                  <input
                    v-model.number="rule.deposit_bonus_percentage"
                    type="number"
                    class="w-full mt-1 p-2 bg-slate-800 border border-slate-600 rounded text-sm"
                  />
                </label>
                <label class="block">
                  <span class="text-xs text-slate-400">Min deposit ($)</span>
                  <input
                    v-model.number="rule.deposit_bonus_min_amount"
                    type="number"
                    class="w-full mt-1 p-2 bg-slate-800 border border-slate-600 rounded text-sm"
                  />
                </label>
                <label class="block">
                  <span class="text-xs text-slate-400">Max bonus ($)</span>
                  <input
                    v-model.number="rule.deposit_bonus_max_bonus"
                    type="number"
                    class="w-full mt-1 p-2 bg-slate-800 border border-slate-600 rounded text-sm"
                  />
                </label>
                <label class="flex items-center gap-2">
                  <input
                    v-model="rule.deposit_bonus_first_deposit_only"
                    type="checkbox"
                  />
                  <span class="text-sm">First deposit only</span>
                </label>
                <label class="block">
                  <span class="text-xs text-slate-400">Bonus message</span>
                  <input
                    v-model="rule.deposit_bonus_message"
                    type="text"
                    class="w-full mt-1 p-2 bg-slate-800 border border-slate-600 rounded text-sm"
                  />
                </label>
              </div>
            </div>

            <!-- Cashout Section -->
            <div>
              <h3 class="text-sm font-medium mb-3">Cashout Rules</h3>
              <div class="grid grid-cols-2 gap-4">
                <label class="flex items-center gap-2">
                  <input v-model="rule.cashout_enabled" type="checkbox" />
                  <span class="text-sm">Cashout enabled</span>
                </label>
                <label class="block">
                  <span class="text-xs text-slate-400">Min multiplier (x)</span>
                  <input
                    v-model.number="rule.cashout_min_multiplier"
                    type="number"
                    step="0.5"
                    class="w-full mt-1 p-2 bg-slate-800 border border-slate-600 rounded text-sm"
                  />
                </label>
                <label class="block">
                  <span class="text-xs text-slate-400">Max multiplier (x)</span>
                  <input
                    v-model.number="rule.cashout_max_multiplier"
                    type="number"
                    step="0.5"
                    class="w-full mt-1 p-2 bg-slate-800 border border-slate-600 rounded text-sm"
                  />
                </label>
                <label class="block">
                  <span class="text-xs text-slate-400">Max cashout ($)</span>
                  <input
                    v-model.number="rule.cashout_max_amount"
                    type="number"
                    class="w-full mt-1 p-2 bg-slate-800 border border-slate-600 rounded text-sm"
                  />
                </label>
                <label class="block">
                  <span class="text-xs text-slate-400">Min cashout ($)</span>
                  <input
                    v-model.number="rule.cashout_min_amount"
                    type="number"
                    class="w-full mt-1 p-2 bg-slate-800 border border-slate-600 rounded text-sm"
                  />
                </label>
                <label class="flex items-center gap-2">
                  <input
                    v-model="rule.cashout_require_screenshot"
                    type="checkbox"
                  />
                  <span class="text-sm">Require screenshot</span>
                </label>
              </div>
              <label class="block mt-4">
                <span class="text-xs text-slate-400"
                  >Cashout rules text (shown to customer)</span
                >
                <textarea
                  v-model="rule.cashout_rules_text"
                  rows="3"
                  class="w-full mt-1 p-2 bg-slate-800 border border-slate-600 rounded text-sm"
                />
              </label>
            </div>

            <!-- Links Section -->
            <div>
              <h3 class="text-sm font-medium mb-3">Game Links</h3>
              <div class="grid grid-cols-2 gap-4">
                <label class="block">
                  <span class="text-xs text-slate-400">Download URL</span>
                  <input
                    v-model="rule.game_download_url"
                    type="url"
                    class="w-full mt-1 p-2 bg-slate-800 border border-slate-600 rounded text-sm"
                  />
                </label>
                <label class="block">
                  <span class="text-xs text-slate-400">Web URL</span>
                  <input
                    v-model="rule.game_web_url"
                    type="url"
                    class="w-full mt-1 p-2 bg-slate-800 border border-slate-600 rounded text-sm"
                  />
                </label>
                <label class="flex items-center gap-2">
                  <input
                    v-model="rule.auto_send_link_on_create"
                    type="checkbox"
                  />
                  <span class="text-sm">Auto-send link on account create</span>
                </label>
              </div>
            </div>

            <button
              class="px-4 py-2 bg-indigo-600 hover:bg-indigo-500 rounded text-sm font-medium"
              @click="saveRule(rule)"
            >
              Save
            </button>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
