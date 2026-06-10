<script>
import PlayerTiersAPI from '../../../../api/playerTiers';
import { useAlert } from 'dashboard/composables';

const TIER_NAMES = ['regular', 'new_player', 'vip', 'selected', 'blocked'];

export default {
  data() {
    return {
      tiers: [],
      loading: true,
      editingId: null,
      adding: false,
      saving: false,
      TIER_NAMES,
      newTier: this.blankTier(),
    };
  },
  mounted() {
    this.fetchTiers();
  },
  methods: {
    blankTier() {
      return {
        name: 'regular',
        color: '#888888',
        badge_text: '',
        sort_order: 0,
        auto_promote_after_deposits: null,
        auto_promote_deposit_threshold: null,
      };
    },
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
    toggleEdit(id) {
      this.editingId = this.editingId === id ? null : id;
    },
    startAdd() {
      this.newTier = this.blankTier();
      this.adding = true;
    },
    async createTier() {
      this.saving = true;
      try {
        const accountId = this.$route.params.accountId;
        await PlayerTiersAPI.createPlayerTier(accountId, this.newTier);
        useAlert('Tier created');
        this.adding = false;
        await this.fetchTiers();
      } catch (e) {
        useAlert(
          e.response?.data?.errors?.join(', ') || 'Failed to create tier'
        );
        console.error(e);
      } finally {
        this.saving = false;
      }
    },
    async saveTier(tier) {
      this.saving = true;
      try {
        const accountId = this.$route.params.accountId;
        await PlayerTiersAPI.updatePlayerTier(accountId, tier.id, {
          name: tier.name,
          color: tier.color,
          badge_text: tier.badge_text,
          sort_order: tier.sort_order,
          auto_promote_after_deposits: tier.auto_promote_after_deposits,
          auto_promote_deposit_threshold: tier.auto_promote_deposit_threshold,
        });
        useAlert('Tier saved');
      } catch (e) {
        useAlert(e.response?.data?.errors?.join(', ') || 'Failed to save tier');
        console.error(e);
      } finally {
        this.saving = false;
      }
    },
    async deleteTier(tier) {
      // eslint-disable-next-line no-alert
      if (
        !window.confirm(
          `Delete tier "${tier.name}"? Contacts on this tier will be unassigned.`
        )
      ) {
        return;
      }
      try {
        const accountId = this.$route.params.accountId;
        await PlayerTiersAPI.deletePlayerTier(accountId, tier.id);
        useAlert('Tier deleted');
        await this.fetchTiers();
      } catch (e) {
        useAlert('Failed to delete tier');
        console.error(e);
      }
    },
  },
};
</script>

<template>
  <div class="pat-tpage flex-1 overflow-auto p-6">
    <div class="max-w-3xl">
      <div class="flex items-center justify-between mb-4">
        <h2 class="text-lg font-medium">Player Tiers</h2>
        <button
          class="px-3 py-1.5 bg-indigo-600 hover:bg-indigo-500 rounded text-sm font-medium"
          @click="startAdd"
        >
          + Add Tier
        </button>
      </div>
      <p class="text-sm text-slate-400 mb-6">
        Define player tiers with different rules and limits.
      </p>

      <!-- New tier form -->
      <div v-if="adding" class="border border-indigo-600 rounded-lg p-4 mb-6">
        <h3 class="text-sm font-medium mb-3">New Tier</h3>
        <div class="grid grid-cols-2 gap-4">
          <label class="block">
            <span class="text-xs text-slate-400">Name</span>
            <select
              v-model="newTier.name"
              class="w-full mt-1 p-2 bg-slate-800 border border-slate-600 rounded text-sm"
            >
              <option v-for="n in TIER_NAMES" :key="n" :value="n">
                {{ n }}
              </option>
            </select>
          </label>
          <label class="block">
            <span class="text-xs text-slate-400">Color</span>
            <div class="flex items-center gap-2 mt-1">
              <input
                v-model="newTier.color"
                type="color"
                class="h-9 w-12 bg-slate-800 border border-slate-600 rounded"
              />
              <input
                v-model="newTier.color"
                type="text"
                placeholder="#888888"
                class="flex-1 p-2 bg-slate-800 border border-slate-600 rounded text-sm"
              />
            </div>
          </label>
          <label class="block">
            <span class="text-xs text-slate-400">Badge text</span>
            <input
              v-model="newTier.badge_text"
              type="text"
              class="w-full mt-1 p-2 bg-slate-800 border border-slate-600 rounded text-sm"
            />
          </label>
          <label class="block">
            <span class="text-xs text-slate-400">Sort order</span>
            <input
              v-model.number="newTier.sort_order"
              type="number"
              class="w-full mt-1 p-2 bg-slate-800 border border-slate-600 rounded text-sm"
            />
          </label>
          <label class="block">
            <span class="text-xs text-slate-400"
              >Auto-promote after deposits</span
            >
            <input
              v-model.number="newTier.auto_promote_after_deposits"
              type="number"
              class="w-full mt-1 p-2 bg-slate-800 border border-slate-600 rounded text-sm"
            />
          </label>
          <label class="block">
            <span class="text-xs text-slate-400"
              >Auto-promote deposit threshold ($)</span
            >
            <input
              v-model.number="newTier.auto_promote_deposit_threshold"
              type="number"
              step="0.01"
              class="w-full mt-1 p-2 bg-slate-800 border border-slate-600 rounded text-sm"
            />
          </label>
        </div>
        <div class="flex gap-2 mt-4">
          <button
            class="px-4 py-2 bg-indigo-600 hover:bg-indigo-500 rounded text-sm font-medium disabled:opacity-50"
            :disabled="saving"
            @click="createTier"
          >
            {{ saving ? 'Saving...' : 'Create' }}
          </button>
          <button
            class="px-4 py-2 bg-slate-700 hover:bg-slate-600 rounded text-sm"
            @click="adding = false"
          >
            Cancel
          </button>
        </div>
      </div>

      <div v-if="loading" class="flex flex-col gap-3">
        <div v-for="n in 4" :key="n" class="pat-skel h-10 w-full" />
      </div>

      <div v-else class="space-y-3">
        <p v-if="!tiers.length" class="text-sm text-slate-400 py-8 text-center">
          No player tiers yet. Create one to segment players by deposit volume
          or activity.
        </p>
        <div
          v-for="tier in tiers"
          :key="tier.id"
          class="border border-slate-700 rounded-lg"
        >
          <div class="flex items-center gap-4 p-4">
            <span
              class="w-3 h-3 rounded-full"
              :style="{ backgroundColor: tier.color }"
            />
            <div class="flex-1">
              <div class="font-medium text-sm">
                {{ tier.badge_text || tier.name }}
              </div>
              <div class="text-xs text-slate-400">{{ tier.name }}</div>
            </div>
            <span class="text-xs text-slate-500">
              {{ Object.keys(tier.rule_overrides || {}).length }} overrides
            </span>
            <button
              class="px-3 py-1.5 bg-slate-700 hover:bg-slate-600 rounded text-xs"
              @click="toggleEdit(tier.id)"
            >
              {{ editingId === tier.id ? 'Close' : 'Edit' }}
            </button>
            <button
              class="px-3 py-1.5 bg-red-900 hover:bg-red-800 text-red-200 rounded text-xs"
              @click="deleteTier(tier)"
            >
              Delete
            </button>
          </div>

          <!-- Inline editor -->
          <div
            v-if="editingId === tier.id"
            class="p-4 border-t border-slate-700"
          >
            <div class="grid grid-cols-2 gap-4">
              <label class="block">
                <span class="text-xs text-slate-400">Name</span>
                <select
                  v-model="tier.name"
                  class="w-full mt-1 p-2 bg-slate-800 border border-slate-600 rounded text-sm"
                >
                  <option v-for="n in TIER_NAMES" :key="n" :value="n">
                    {{ n }}
                  </option>
                </select>
              </label>
              <label class="block">
                <span class="text-xs text-slate-400">Color</span>
                <div class="flex items-center gap-2 mt-1">
                  <input
                    v-model="tier.color"
                    type="color"
                    class="h-9 w-12 bg-slate-800 border border-slate-600 rounded"
                  />
                  <input
                    v-model="tier.color"
                    type="text"
                    placeholder="#888888"
                    class="flex-1 p-2 bg-slate-800 border border-slate-600 rounded text-sm"
                  />
                </div>
              </label>
              <label class="block">
                <span class="text-xs text-slate-400">Badge text</span>
                <input
                  v-model="tier.badge_text"
                  type="text"
                  class="w-full mt-1 p-2 bg-slate-800 border border-slate-600 rounded text-sm"
                />
              </label>
              <label class="block">
                <span class="text-xs text-slate-400">Sort order</span>
                <input
                  v-model.number="tier.sort_order"
                  type="number"
                  class="w-full mt-1 p-2 bg-slate-800 border border-slate-600 rounded text-sm"
                />
              </label>
              <label class="block">
                <span class="text-xs text-slate-400"
                  >Auto-promote after deposits</span
                >
                <input
                  v-model.number="tier.auto_promote_after_deposits"
                  type="number"
                  class="w-full mt-1 p-2 bg-slate-800 border border-slate-600 rounded text-sm"
                />
              </label>
              <label class="block">
                <span class="text-xs text-slate-400"
                  >Auto-promote deposit threshold ($)</span
                >
                <input
                  v-model.number="tier.auto_promote_deposit_threshold"
                  type="number"
                  step="0.01"
                  class="w-full mt-1 p-2 bg-slate-800 border border-slate-600 rounded text-sm"
                />
              </label>
            </div>
            <button
              class="mt-4 px-4 py-2 bg-indigo-600 hover:bg-indigo-500 rounded text-sm font-medium disabled:opacity-50"
              :disabled="saving"
              @click="saveTier(tier)"
            >
              {{ saving ? 'Saving...' : 'Save' }}
            </button>
          </div>
        </div>
      </div>

      <p class="text-xs text-slate-500 mt-4">
        Tier names are restricted to the 5 system tiers (regular, new_player,
        vip, selected, blocked).
      </p>
    </div>
  </div>
</template>
