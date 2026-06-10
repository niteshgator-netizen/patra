<script>
import ReferralsAPI from '../../../../api/referrals';
import { useAlert } from 'dashboard/composables';

export default {
  data() {
    return {
      referrals: [],
      loading: true,
      settings: {
        referral_enabled: false,
        referral_bonus_referrer: 5.0,
        referral_bonus_new_player: 5.0,
        referral_bonus_type: 'freeplay',
        referral_require_deposit: true,
        referral_tracking_method: 'manual',
        referral_message_referrer: '',
        referral_message_new_player: '',
      },
      settingsLoading: true,
      savingSettings: false,
    };
  },
  mounted() {
    this.fetchSettings();
    this.fetchReferrals();
  },
  methods: {
    async fetchSettings() {
      try {
        const accountId = this.$route.params.accountId;
        const { data } = await ReferralsAPI.getReferralSettings(accountId);
        this.settings = { ...this.settings, ...data };
      } catch (e) {
        console.error('Failed to fetch referral settings:', e);
      } finally {
        this.settingsLoading = false;
      }
    },
    async saveSettings() {
      this.savingSettings = true;
      try {
        const accountId = this.$route.params.accountId;
        const { data } = await ReferralsAPI.updateReferralSettings(
          accountId,
          this.settings
        );
        this.settings = { ...this.settings, ...data };
        useAlert('Referral settings saved');
      } catch (e) {
        useAlert('Failed to save referral settings');
        console.error(e);
      } finally {
        this.savingSettings = false;
      }
    },
    async fetchReferrals() {
      try {
        const accountId = this.$route.params.accountId;
        const { data } = await ReferralsAPI.getReferrals(accountId);
        this.referrals = data;
      } catch (e) {
        console.error('Failed to fetch referrals:', e);
      } finally {
        this.loading = false;
      }
    },
  },
};
</script>

<template>
  <div class="pat-tpage flex-1 overflow-auto p-6">
    <div class="max-w-3xl">
      <h2 class="text-lg font-medium mb-4">Referrals</h2>
      <p class="text-sm text-slate-400 mb-6">
        Track player referrals and bonuses.
      </p>

      <!-- Settings Section -->
      <div class="border border-slate-700 rounded-lg p-4 mb-8">
        <h3 class="text-sm font-medium mb-4">Referral Settings</h3>

        <div v-if="settingsLoading" class="flex flex-col gap-3">
          <div v-for="n in 2" :key="n" class="pat-skel h-10 w-full" />
        </div>

        <div v-else class="space-y-6">
          <div class="grid grid-cols-2 gap-4">
            <label class="flex items-center gap-2">
              <input v-model="settings.referral_enabled" type="checkbox" />
              <span class="text-sm">Referrals enabled</span>
            </label>
            <label class="flex items-center gap-2">
              <input
                v-model="settings.referral_require_deposit"
                type="checkbox"
              />
              <span class="text-sm">Require deposit before payout</span>
            </label>
            <label class="block">
              <span class="text-xs text-slate-400">Referrer bonus ($)</span>
              <input
                v-model.number="settings.referral_bonus_referrer"
                type="number"
                step="0.01"
                class="w-full mt-1 p-2 bg-slate-800 border border-slate-600 rounded text-sm"
              />
            </label>
            <label class="block">
              <span class="text-xs text-slate-400">New player bonus ($)</span>
              <input
                v-model.number="settings.referral_bonus_new_player"
                type="number"
                step="0.01"
                class="w-full mt-1 p-2 bg-slate-800 border border-slate-600 rounded text-sm"
              />
            </label>
            <label class="block">
              <span class="text-xs text-slate-400">Bonus type</span>
              <select
                v-model="settings.referral_bonus_type"
                class="w-full mt-1 p-2 bg-slate-800 border border-slate-600 rounded text-sm"
              >
                <option value="freeplay">Freeplay</option>
                <option value="deposit_bonus">Deposit bonus</option>
                <option value="credit">Credit</option>
              </select>
            </label>
            <label class="block">
              <span class="text-xs text-slate-400">Tracking method</span>
              <select
                v-model="settings.referral_tracking_method"
                class="w-full mt-1 p-2 bg-slate-800 border border-slate-600 rounded text-sm"
              >
                <option value="manual">Manual</option>
                <option value="auto">Auto</option>
              </select>
            </label>
            <label class="block">
              <span class="text-xs text-slate-400">Referrer message</span>
              <input
                v-model="settings.referral_message_referrer"
                type="text"
                class="w-full mt-1 p-2 bg-slate-800 border border-slate-600 rounded text-sm"
              />
            </label>
            <label class="block">
              <span class="text-xs text-slate-400">New player message</span>
              <input
                v-model="settings.referral_message_new_player"
                type="text"
                class="w-full mt-1 p-2 bg-slate-800 border border-slate-600 rounded text-sm"
              />
            </label>
          </div>

          <button
            class="px-4 py-2 bg-indigo-600 hover:bg-indigo-500 rounded text-sm font-medium disabled:opacity-50"
            :disabled="savingSettings"
            @click="saveSettings"
          >
            {{ savingSettings ? 'Saving...' : 'Save Settings' }}
          </button>
        </div>
      </div>

      <!-- Referrals List -->
      <h3 class="text-sm font-medium mb-3">Referral History</h3>
      <div v-if="loading" class="flex flex-col gap-3">
        <div v-for="n in 4" :key="n" class="pat-skel h-10 w-full" />
      </div>

      <div v-else>
        <div v-if="referrals.length === 0" class="text-sm text-slate-500">
          No referrals yet.
        </div>
        <div v-else class="space-y-2">
          <div
            v-for="ref in referrals"
            :key="ref.id"
            class="flex items-center gap-4 p-3 border border-slate-700 rounded"
          >
            <div class="flex-1 text-sm">
              <span class="font-medium">{{
                ref.referrer_contact?.name || ref.referrer_contact_id
              }}</span>
              <span class="text-slate-400"> → </span>
              <span>{{
                ref.referred_contact?.name ||
                ref.referred_contact_id ||
                'pending'
              }}</span>
            </div>
            <span
              class="text-xs px-2 py-1 rounded"
              :class="{
                'bg-yellow-900 text-yellow-300': ref.status === 'pending',
                'bg-green-900 text-green-300': ref.status === 'paid',
                'bg-blue-900 text-blue-300': ref.status === 'verified',
                'bg-red-900 text-red-300': ref.status === 'rejected',
              }"
              >{{ ref.status }}</span
            >
            <span class="text-xs text-slate-400"
              >${{ ref.bonus_amount || 0 }}</span
            >
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
