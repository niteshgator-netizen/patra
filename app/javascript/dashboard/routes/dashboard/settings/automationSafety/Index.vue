<template>
  <div class="pat-tpage flex-1 overflow-auto p-6">
    <div class="max-w-2xl">
      <h2 class="text-lg font-medium mb-4">Automation &amp; Safety</h2>
      <p class="text-sm text-slate-400 mb-6">Control game transfers, player win-back, and fraud guards.</p>

      <div v-if="loading" class="flex flex-col gap-3"><div v-for="n in 4" :key="n" class="pat-skel h-10 w-full" /></div>

      <div v-else class="space-y-8">
        <!-- TRANSFER -->
        <section class="space-y-4">
          <h3 class="text-sm font-medium">Transfer</h3>

          <label class="block">
            <span class="text-sm">Transfer mode</span>
            <select v-model="pref.transfer_mode" class="w-full mt-1 p-2 bg-slate-800 border border-slate-600 rounded text-sm">
              <option value="whole">Transfer whole balance</option>
              <option value="deposit_only">Transfer deposit only</option>
            </select>
            <span class="text-xs text-slate-500">When a player's winnings are below the cashout limit and they switch games.</span>
          </label>

          <label class="block">
            <span class="text-sm">Deposit shortfall handling</span>
            <select v-model="pref.transfer_deposit_shortfall_mode" class="w-full mt-1 p-2 bg-slate-800 border border-slate-600 rounded text-sm">
              <option value="transfer_available">Transfer what they have</option>
              <option value="refuse">Refuse &amp; flag</option>
            </select>
            <span class="text-xs text-slate-500">If their current balance is less than their deposit (only relevant for "deposit only").</span>
          </label>
        </section>

        <hr class="border-slate-700" />

        <!-- WIN-BACK -->
        <section class="space-y-4">
          <h3 class="text-sm font-medium">Win-back</h3>
          <p class="text-xs text-slate-500">Re-engage dormant players. Days quiet before Bella reaches out, per tier.</p>

          <label class="flex items-center gap-2">
            <input v-model="pref.winback_enabled" type="checkbox" />
            <span class="text-sm">Win-back enabled</span>
          </label>

          <div class="grid grid-cols-3 gap-4">
            <label class="block">
              <span class="text-xs text-slate-400">VIP — days quiet</span>
              <input v-model.number="pref.winback_dormant_days_vip" type="number" min="1" class="w-full mt-1 p-2 bg-slate-800 border border-slate-600 rounded text-sm" />
            </label>
            <label class="block">
              <span class="text-xs text-slate-400">Regular — days quiet</span>
              <input v-model.number="pref.winback_dormant_days_regular" type="number" min="1" class="w-full mt-1 p-2 bg-slate-800 border border-slate-600 rounded text-sm" />
            </label>
            <label class="block">
              <span class="text-xs text-slate-400">New — days quiet</span>
              <input v-model.number="pref.winback_dormant_days_new" type="number" min="1" class="w-full mt-1 p-2 bg-slate-800 border border-slate-600 rounded text-sm" />
            </label>
          </div>
        </section>

        <hr class="border-slate-700" />

        <!-- FRAUD & SAFETY -->
        <section class="space-y-4">
          <h3 class="text-sm font-medium">Fraud &amp; Safety</h3>

          <div>
            <p class="text-xs text-slate-500 mb-2">Flag a player who cashes out N times within M hours.</p>
            <div class="grid grid-cols-2 gap-4">
              <label class="block">
                <span class="text-xs text-slate-400">Cashout count (N)</span>
                <input v-model.number="pref.fraud_cashout_velocity_count" type="number" min="1" class="w-full mt-1 p-2 bg-slate-800 border border-slate-600 rounded text-sm" />
              </label>
              <label class="block">
                <span class="text-xs text-slate-400">Within hours (M)</span>
                <input v-model.number="pref.fraud_cashout_velocity_hours" type="number" min="1" class="w-full mt-1 p-2 bg-slate-800 border border-slate-600 rounded text-sm" />
              </label>
            </div>
          </div>

          <label class="flex items-center gap-2">
            <input v-model="pref.fraud_duplicate_payment_check" type="checkbox" />
            <span class="text-sm">Duplicate-payment check</span>
          </label>
          <span class="text-xs text-slate-500 block -mt-2">Block double-loading the same amount within 10 minutes.</span>
        </section>

        <hr class="border-slate-700" />

        <!-- PAYMENT -->
        <section class="space-y-4">
          <h3 class="text-sm font-medium">Payment</h3>

          <label class="block">
            <span class="text-sm">Payment-question reply source</span>
            <select v-model="pref.payment_reply_source" class="w-full mt-1 p-2 bg-slate-800 border border-slate-600 rounded text-sm">
              <option value="canned">Canned response</option>
              <option value="handles">Active handles</option>
            </select>
            <span class="text-xs text-slate-500">How Bella answers "what payment methods?". Either way, only platform names are shown — never a handle.</span>
          </label>
        </section>

        <button
          class="px-4 py-2 bg-indigo-600 hover:bg-indigo-500 rounded text-sm font-medium"
          @click="save"
        >
          Save
        </button>
      </div>
    </div>
  </div>
</template>

<script>
import ReplyPreferencesAPI from '../../../../api/replyPreferences';
import { useAlert } from 'dashboard/composables';

export default {
  data() {
    return {
      pref: {
        transfer_mode: 'whole',
        transfer_deposit_shortfall_mode: 'transfer_available',
        winback_enabled: false,
        winback_dormant_days_vip: 3,
        winback_dormant_days_regular: 14,
        winback_dormant_days_new: 7,
        fraud_cashout_velocity_count: 3,
        fraud_cashout_velocity_hours: 24,
        fraud_duplicate_payment_check: true,
        payment_reply_source: 'canned',
      },
      loading: true,
    };
  },
  mounted() {
    this.fetchPref();
  },
  methods: {
    async fetchPref() {
      try {
        const accountId = this.$route.params.accountId;
        const { data } = await ReplyPreferencesAPI.getReplyPreference(accountId);
        this.pref = { ...this.pref, ...data };
      } catch (e) {
        console.error('Failed to fetch automation settings:', e);
      } finally {
        this.loading = false;
      }
    },
    async save() {
      try {
        const accountId = this.$route.params.accountId;
        await ReplyPreferencesAPI.updateReplyPreference(accountId, this.pref);
        useAlert('Automation & safety settings saved');
      } catch (e) {
        useAlert('Failed to save');
        console.error(e);
      }
    },
  },
};
</script>
