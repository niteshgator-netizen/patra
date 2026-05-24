<script setup>
import { onMounted, onUnmounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import CashierClaimsAPI from 'dashboard/api/cashierClaims';

const { t } = useI18n();
const claims = ref([]);
let pollInterval = null;

const load = async () => {
  const { data } = await CashierClaimsAPI.get();
  claims.value = data;
};

const claim = async id => {
  await CashierClaimsAPI.claim(id);
  await load();
};

const complete = async id => {
  await CashierClaimsAPI.complete(id);
  await load();
};

const timeRemaining = claim => {
  if (!claim.expires_at) return '—';
  const ms = new Date(claim.expires_at) - Date.now();
  return ms > 0 ? `${Math.ceil(ms / 1000)}s` : 'Expired';
};

onMounted(() => {
  load();
  pollInterval = setInterval(load, 5000);
});

onUnmounted(() => clearInterval(pollInterval));
</script>

<template>
  <div class="flex flex-col gap-2 p-4 border rounded-xl border-n-weak">
    <h3 class="text-sm font-semibold">{{ $t('PATRA.CASHIER.QUEUE_TITLE') }}</h3>
    <div v-if="!claims.length" class="text-xs text-n-slate-11">
      {{ $t('PATRA.CASHIER.EMPTY') }}
    </div>
    <div
      v-for="claim in claims"
      :key="claim.id"
      class="flex items-center justify-between p-2 text-sm rounded-lg bg-n-alpha-1"
    >
      <div>
        <span class="font-medium">{{ claim.action_type }}</span>
        ${{ claim.amount }} · {{ claim.game_slug }}
        <span class="text-xs text-n-slate-11">({{ timeRemaining(claim) }})</span>
      </div>
      <div class="flex gap-1">
        <button
          v-if="claim.status === 'pending'"
          class="px-2 py-1 text-xs text-white rounded-lg bg-n-brand"
          @click="claim(claim.id)"
        >
          {{ $t('PATRA.CASHIER.CLAIM') }}
        </button>
        <button
          v-if="claim.status === 'claimed'"
          class="px-2 py-1 text-xs rounded-lg border border-n-weak"
          @click="complete(claim.id)"
        >
          {{ $t('PATRA.CASHIER.COMPLETE') }}
        </button>
      </div>
    </div>
  </div>
</template>
