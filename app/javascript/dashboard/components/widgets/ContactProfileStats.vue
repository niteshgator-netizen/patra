<script setup>
import { computed } from 'vue';

const props = defineProps({
  contact: {
    type: Object,
    default: () => ({}),
  },
});

const stats = computed(() => props.contact?.profile_stats || {});

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

const depositsLabel = computed(() => {
  const count = stats.value.deposits?.count ?? 0;
  const total = formatMoney(stats.value.deposits?.total);
  return `${count} · ${total}`;
});

const cashoutsLabel = computed(() => {
  const count = stats.value.cashouts?.count ?? 0;
  const total = formatMoney(stats.value.cashouts?.total);
  return `${count} · ${total}`;
});

const onStatHover = e => {
  const card = e.currentTarget;
  const rect = card.getBoundingClientRect();
  card.style.setProperty('--mx', `${e.clientX - rect.left}px`);
  card.style.setProperty('--my', `${e.clientY - rect.top}px`);
};
</script>

<template>
  <div v-if="hasStats" class="ctx-section">
    <div class="ctx-label">{{ $t('PATRA.PROFILE.STATS') }}</div>
    <div class="stat-row">
      <div class="stat js-spot" @mousemove="onStatHover">
        <div class="n p">{{ stats.conversation_count ?? 0 }}</div>
        <div class="l">{{ $t('PATRA.PROFILE.CONVERSATIONS') }}</div>
      </div>
      <div class="stat js-spot" @mousemove="onStatHover">
        <div class="n g">{{ depositsLabel }}</div>
        <div class="l">{{ $t('PATRA.PROFILE.DEPOSITS') }}</div>
      </div>
      <div class="stat js-spot" @mousemove="onStatHover">
        <div class="n">{{ cashoutsLabel }}</div>
        <div class="l">{{ $t('PATRA.PROFILE.CASHOUTS') }}</div>
      </div>
      <div class="stat js-spot" @mousemove="onStatHover">
        <div class="n sm">{{ humanizePayment(stats.preferred_payment) }}</div>
        <div class="l">{{ $t('PATRA.PROFILE.PREFERRED_PAYMENT') }}</div>
      </div>
    </div>
    <div class="field">
      <span class="k">{{ $t('PATRA.PROFILE.LAST_GAME') }}</span>
      <span class="v">{{ humanizeGame(stats.last_game) }}</span>
    </div>
  </div>
</template>
