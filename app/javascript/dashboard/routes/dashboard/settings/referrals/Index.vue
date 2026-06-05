<template>
  <div class="flex-1 overflow-auto p-6">
    <div class="max-w-3xl">
      <h2 class="text-lg font-medium mb-4">Referrals</h2>
      <p class="text-sm text-slate-400 mb-6">Track player referrals and bonuses.</p>

      <div v-if="loading" class="text-sm text-slate-400">Loading...</div>

      <div v-else>
        <div v-if="referrals.length === 0" class="text-sm text-slate-500">No referrals yet.</div>
        <div v-else class="space-y-2">
          <div
            v-for="ref in referrals"
            :key="ref.id"
            class="flex items-center gap-4 p-3 border border-slate-700 rounded"
          >
            <div class="flex-1 text-sm">
              <span class="font-medium">{{ ref.referrer_contact?.name || ref.referrer_contact_id }}</span>
              <span class="text-slate-400"> → </span>
              <span>{{ ref.referred_contact?.name || ref.referred_contact_id || 'pending' }}</span>
            </div>
            <span
              class="text-xs px-2 py-1 rounded"
              :class="{
                'bg-yellow-900 text-yellow-300': ref.status === 'pending',
                'bg-green-900 text-green-300': ref.status === 'paid',
                'bg-blue-900 text-blue-300': ref.status === 'verified',
                'bg-red-900 text-red-300': ref.status === 'rejected',
              }"
            >{{ ref.status }}</span>
            <span class="text-xs text-slate-400">${{ ref.bonus_amount || 0 }}</span>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script>
import ReferralsAPI from '../../../../api/referrals';

export default {
  data() {
    return { referrals: [], loading: true };
  },
  mounted() {
    this.fetchReferrals();
  },
  methods: {
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
