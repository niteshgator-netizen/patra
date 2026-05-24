<script setup>
import { computed } from 'vue';
import { dynamicTime } from 'shared/helpers/timeHelper';

const props = defineProps({
  contact: {
    type: Object,
    default: () => ({}),
  },
});

const stats = computed(() => props.contact?.profile_stats || {});

const tierEmoji = computed(() => {
  const tier = (stats.value.loyalty_tier || '').toString().toLowerCase();
  if (tier === 'vip' || tier === 'loyal') return '🌟';
  if (tier === 'regular') return '🔵';
  return '🟢';
});

const tierClass = computed(() => {
  const tier = (stats.value.loyalty_tier || '').toString().toLowerCase();
  const map = {
    vip: 'text-amber-600 dark:text-amber-400',
    loyal: 'text-violet-600 dark:text-violet-400',
    regular: 'text-teal-600 dark:text-teal-400',
    new: 'text-green-600 dark:text-green-400',
  };
  return map[tier] || 'text-n-slate-11';
});

const activeLabel = computed(() => {
  const raw = props.contact?.last_activity_at;
  if (!raw) return null;
  const seconds = typeof raw === 'number' ? raw : parseInt(String(raw), 10);
  if (Number.isNaN(seconds) || seconds <= 0) return null;
  return dynamicTime(seconds);
});

function formatMoney(val) {
  const n = Number.parseFloat(val);
  if (Number.isNaN(n)) return '$0';
  return new Intl.NumberFormat(undefined, {
    style: 'currency',
    currency: 'USD',
    maximumFractionDigits: 0,
  }).format(n);
}

function humanizeGame(slug) {
  if (!slug) return '—';
  return String(slug)
    .replace(/_/g, ' ')
    .replace(/\b\w/g, c => c.toUpperCase());
}

function humanizePayment(method) {
  if (!method || method === 'Unknown') return '—';
  return String(method)
    .replace(/_/g, ' ')
    .replace(/\b\w/g, c => c.toUpperCase());
}

const hasStats = computed(() => Boolean(stats.value && props.contact?.id));
</script>

<template>
  <div
    v-if="hasStats"
    class="mx-4 mb-3 rounded-lg border border-n-weak bg-n-solid-1 p-3 text-sm"
  >
    <div class="mb-2 flex flex-wrap items-center gap-2">
      <span v-if="stats.loyalty_tier" class="font-medium capitalize" :class="tierClass">
        {{ tierEmoji }} {{ stats.loyalty_tier }}
      </span>
      <span v-if="activeLabel" class="text-xs text-n-slate-11">
        · {{ $t('PATRA.PROFILE.ACTIVE_AGO', { time: activeLabel }) }}
      </span>
    </div>
    <div class="border-t border-n-weak pt-2">
      <p class="mb-2 text-xs font-semibold uppercase tracking-wide text-n-slate-11">
        📊 {{ $t('PATRA.PROFILE.STATS') }}
      </p>
      <dl class="m-0 space-y-1 text-xs">
        <div class="flex justify-between gap-2">
          <dt class="text-n-slate-11">{{ $t('PATRA.PROFILE.CONVERSATIONS') }}</dt>
          <dd class="m-0 font-medium text-n-slate-12">
            {{ stats.conversation_count ?? 0 }}
          </dd>
        </div>
        <div class="flex justify-between gap-2">
          <dt class="text-n-slate-11">{{ $t('PATRA.PROFILE.DEPOSITS') }}</dt>
          <dd class="m-0 font-medium text-n-slate-12">
            {{ stats.deposits?.count ?? 0 }}
            ({{ formatMoney(stats.deposits?.total) }})
          </dd>
        </div>
        <div class="flex justify-between gap-2">
          <dt class="text-n-slate-11">{{ $t('PATRA.PROFILE.CASHOUTS') }}</dt>
          <dd class="m-0 font-medium text-n-slate-12">
            {{ stats.cashouts?.count ?? 0 }}
            ({{ formatMoney(stats.cashouts?.total) }})
          </dd>
        </div>
        <div class="flex justify-between gap-2">
          <dt class="text-n-slate-11">{{ $t('PATRA.PROFILE.PREFERRED_PAYMENT') }}</dt>
          <dd class="m-0 font-medium text-n-slate-12">
            {{ humanizePayment(stats.preferred_payment) }}
          </dd>
        </div>
        <div class="flex justify-between gap-2">
          <dt class="text-n-slate-11">{{ $t('PATRA.PROFILE.LAST_GAME') }}</dt>
          <dd class="m-0 font-medium capitalize text-n-slate-12">
            {{ humanizeGame(stats.last_game) }}
          </dd>
        </div>
      </dl>
    </div>
  </div>
</template>
