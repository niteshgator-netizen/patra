<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  contact: {
    type: Object,
    default: null,
  },
});

const { t } = useI18n();

const attrs = computed(() => {
  const raw = props.contact?.custom_attributes;
  if (!raw || typeof raw !== 'object') return {};
  return { ...raw };
});

const PREDEFINED_ATTR_KEYS = new Set([
  'game_username',
  'preferred_platform',
  'loyalty_tier',
  'deposit_count',
  'total_deposits',
  'total_cashouts',
  'last_deposit_amount',
  'last_deposit_date',
  'last_cashout_date',
  'last_cashout_intent_date',
  'preferred_payment_method',
  'preferred_bonus_percentage',
  'first_contact_date',
  'notes',
]);

function humanizeAttrKey(key) {
  return String(key)
    .replace(/_/g, ' ')
    .replace(/\b\w/g, c => c.toUpperCase());
}

const tierClass = computed(() => {
  const tier = (attrs.value.loyalty_tier || '').toString().toLowerCase();
  const map = {
    vip: 'bg-amber-100 text-amber-950 dark:bg-amber-900/40 dark:text-amber-100',
    loyal: 'bg-violet-100 text-violet-950 dark:bg-violet-900/40 dark:text-violet-100',
    regular: 'bg-teal-100 text-teal-950 dark:bg-teal-900/40 dark:text-teal-100',
    casual: 'bg-slate-100 text-slate-900 dark:bg-slate-800 dark:text-slate-100',
    new: 'bg-n-alpha-2 text-n-slate-12',
  };
  return map[tier] || 'bg-n-alpha-2 text-n-slate-12';
});

function formatMoney(val) {
  const n = Number.parseFloat(val);
  if (Number.isNaN(n)) return '—';
  return new Intl.NumberFormat(undefined, {
    style: 'currency',
    currency: 'USD',
    maximumFractionDigits: 2,
  }).format(n);
}

function formatDate(val) {
  if (!val) return '—';
  const d = new Date(val);
  if (Number.isNaN(d.getTime())) return String(val);
  return d.toLocaleDateString(undefined, {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  });
}

const rows = computed(() => [
  {
    key: 'game_username',
    label: t('PLAYER_PROFILE.FIELDS.GAME_USERNAME'),
    value: attrs.value.game_username,
  },
  {
    key: 'preferred_platform',
    label: t('PLAYER_PROFILE.FIELDS.PREFERRED_PLATFORM'),
    value: attrs.value.preferred_platform,
  },
  {
    key: 'loyalty_tier',
    label: t('PLAYER_PROFILE.FIELDS.LOYALTY_TIER'),
    value: attrs.value.loyalty_tier,
    highlight: true,
  },
  {
    key: 'deposit_count',
    label: t('PLAYER_PROFILE.FIELDS.DEPOSIT_COUNT'),
    value:
      attrs.value.deposit_count != null && attrs.value.deposit_count !== ''
        ? String(attrs.value.deposit_count)
        : '',
  },
  {
    key: 'total_deposits',
    label: t('PLAYER_PROFILE.FIELDS.TOTAL_DEPOSITS'),
    value: formatMoney(attrs.value.total_deposits),
  },
  {
    key: 'total_cashouts',
    label: t('PLAYER_PROFILE.FIELDS.TOTAL_CASHOUTS'),
    value: formatMoney(attrs.value.total_cashouts),
  },
  {
    key: 'last_deposit_amount',
    label: t('PLAYER_PROFILE.FIELDS.LAST_DEPOSIT_AMOUNT'),
    value: formatMoney(attrs.value.last_deposit_amount),
  },
  {
    key: 'last_deposit_date',
    label: t('PLAYER_PROFILE.FIELDS.LAST_DEPOSIT_DATE'),
    value: formatDate(attrs.value.last_deposit_date),
  },
  {
    key: 'last_cashout_date',
    label: t('PLAYER_PROFILE.FIELDS.LAST_CASHOUT_DATE'),
    value: formatDate(attrs.value.last_cashout_date),
  },
  {
    key: 'last_cashout_intent_date',
    label: t('PLAYER_PROFILE.FIELDS.LAST_CASHOUT_INTENT'),
    value: formatDate(attrs.value.last_cashout_intent_date),
  },
  {
    key: 'preferred_payment_method',
    label: t('PLAYER_PROFILE.FIELDS.PREFERRED_PAYMENT'),
    value: attrs.value.preferred_payment_method,
  },
  {
    key: 'preferred_bonus_percentage',
    label: t('PLAYER_PROFILE.FIELDS.PREFERRED_BONUS'),
    value:
      attrs.value.preferred_bonus_percentage != null &&
      attrs.value.preferred_bonus_percentage !== ''
        ? `${attrs.value.preferred_bonus_percentage}%`
        : '',
  },
  {
    key: 'first_contact_date',
    label: t('PLAYER_PROFILE.FIELDS.FIRST_CONTACT'),
    value: formatDate(attrs.value.first_contact_date),
  },
  {
    key: 'notes',
    label: t('PLAYER_PROFILE.FIELDS.NOTES'),
    value: attrs.value.notes,
    multiline: true,
  },
]);

const filledRows = computed(() =>
  rows.value.filter(r => r.value != null && String(r.value).trim() !== '')
);

const extraAttrRows = computed(() => {
  const out = [];
  Object.entries(attrs.value).forEach(([key, value]) => {
    if (PREDEFINED_ATTR_KEYS.has(key)) return;
    if (value == null || String(value).trim() === '') return;
    out.push({
      key: `extra_${key}`,
      label: humanizeAttrKey(key),
      value: typeof value === 'object' ? JSON.stringify(value) : String(value),
    });
  });
  return out.sort((a, b) => a.label.localeCompare(b.label));
});

const displayRows = computed(() => [
  ...filledRows.value,
  ...extraAttrRows.value,
]);

const isEmpty = computed(() => displayRows.value.length === 0);
</script>

<template>
  <div class="rounded-lg border border-n-weak bg-n-solid-1 p-3 text-sm">
    <div
      v-if="attrs.loyalty_tier"
      class="mb-3 flex items-center justify-between gap-2"
    >
      <span class="text-xs font-medium uppercase tracking-wide text-n-slate-11">
        {{ $t('PLAYER_PROFILE.TIER_BADGE') }}
      </span>
      <span
        class="rounded-full px-2.5 py-0.5 text-xs font-semibold capitalize"
        :class="tierClass"
      >
        {{ attrs.loyalty_tier }}
      </span>
    </div>
    <p
      v-if="isEmpty"
      class="m-0 text-n-slate-11"
    >
      {{ $t('PLAYER_PROFILE.EMPTY') }}
    </p>
    <dl v-else class="m-0 space-y-2">
      <div
        v-for="row in displayRows"
        :key="row.key"
        class="min-w-0"
      >
        <dt class="text-xs font-medium text-n-slate-11">
          {{ row.label }}
        </dt>
        <dd
          class="m-0 break-words text-n-slate-12"
          :class="row.multiline ? 'whitespace-pre-wrap' : ''"
        >
          {{ row.value }}
        </dd>
      </div>
    </dl>
  </div>
</template>
