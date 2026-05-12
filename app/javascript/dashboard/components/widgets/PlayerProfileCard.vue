<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';

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
  'patra_finance_logs',
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

function coerceFinanceLogs(val) {
  if (Array.isArray(val)) return val.filter(Boolean);
  if (val && typeof val === 'string') {
    try {
      const parsed = JSON.parse(val);
      return Array.isArray(parsed) ? parsed.filter(Boolean) : [];
    } catch {
      return [];
    }
  }
  return [];
}

function financeLogSortTs(entry) {
  const datePart = entry.transaction_date;
  const timePart = entry.transaction_time;
  if (datePart && timePart) {
    const d = new Date(`${datePart} ${timePart}`);
    if (!Number.isNaN(d.getTime())) return d.getTime();
  }
  if (datePart) {
    const d = new Date(datePart);
    if (!Number.isNaN(d.getTime())) return d.getTime();
  }
  const iso = entry.image_received_at || entry.logged_at;
  if (iso) {
    const d = new Date(iso);
    if (!Number.isNaN(d.getTime())) return d.getTime();
  }
  return 0;
}

const financeLogsSorted = computed(() => {
  const raw = coerceFinanceLogs(attrs.value.patra_finance_logs);
  return [...raw.entries()]
    .sort(([_ia, a], [ib, b]) => {
      const tb = financeLogSortTs(b);
      const ta = financeLogSortTs(a);
      if (tb !== ta) return tb - ta;
      return ib - ia;
    })
    .map(([, e]) => e);
});

const financeLogsExpanded = ref(false);

function isFinanceFlagged(entry) {
  return Boolean(entry?.flag_reason);
}

function financeMemoLine(entry) {
  const raw = entry.note_or_memo;
  if (raw != null && String(raw).trim() !== '') return { type: 'memo', text: String(raw) };
  if (!isFinanceFlagged(entry)) return null;
  if (entry.flag_reason === 'recipient_mismatch') {
    const handle = entry.our_handle_name;
    if (handle != null && String(handle).trim() !== '') {
      return {
        type: 'flag',
        text: t('PLAYER_PROFILE.PAYMENT_SCREENSHOTS.EXPECTED_HANDLE', {
          handle: String(handle),
        }),
      };
    }
  }
  return { type: 'flag', text: t('PLAYER_PROFILE.PAYMENT_SCREENSHOTS.BONUS_NOT_APPLIED') };
}

const financeLogsIndexed = computed(() =>
  financeLogsSorted.value.map((entry, globalIdx) => ({ entry, globalIdx }))
);

const financeLogsVisibleRows = computed(() => {
  const rows = financeLogsIndexed.value;
  const sliced = financeLogsExpanded.value ? rows : rows.slice(0, 5);
  return sliced.map((row, visibleIdx) => {
    const prev = visibleIdx > 0 ? sliced[visibleIdx - 1].entry : null;
    const sameTxAsAbove =
      row.entry.flag_reason === 'duplicate' &&
      visibleIdx > 0 &&
      row.entry.transaction_id != null &&
      String(row.entry.transaction_id) !== '' &&
      prev &&
      String(prev.transaction_id) === String(row.entry.transaction_id);
    return {
      ...row,
      visibleIdx,
      sameTxAsAbove,
      memoLine: financeMemoLine(row.entry),
    };
  });
});

const financeLogsTotal = computed(() => financeLogsSorted.value.length);

const thumbLoadErrors = ref(new Set());

function financeRowDomKey(row) {
  return `${row.globalIdx}-${row.entry.transaction_id || ''}-${row.entry.logged_at || ''}`;
}

function onThumbError(row) {
  const k = financeRowDomKey(row);
  thumbLoadErrors.value = new Set(thumbLoadErrors.value).add(k);
}

function thumbErrored(row) {
  return thumbLoadErrors.value.has(financeRowDomKey(row));
}

function openFinanceFullImage(entry) {
  const url = entry.image_url || entry.image_thumb_url;
  if (!url) return;
  window.open(url, '_blank', 'noopener,noreferrer');
}

watch(
  () => props.contact?.id,
  () => {
    financeLogsExpanded.value = false;
    thumbLoadErrors.value = new Set();
  }
);

function financeSenderName(entry) {
  return (entry.sender_name ?? entry.sender ?? '—').toString();
}

function financeRecipientName(entry) {
  return (entry.recipient_name ?? entry.recipient ?? '—').toString();
}

function financeStatusPill(entry) {
  const fr = entry.flag_reason;
  if (fr === 'duplicate') {
    return {
      text: t('PLAYER_PROFILE.PAYMENT_SCREENSHOTS.STATUS_DUPLICATE'),
      class:
        'bg-n-ruby-9/15 text-n-ruby-11 dark:bg-n-ruby-9/25 dark:text-n-ruby-11',
    };
  }
  if (fr === 'recipient_mismatch') {
    return {
      text: t('PLAYER_PROFILE.PAYMENT_SCREENSHOTS.STATUS_WRONG_RECIPIENT'),
      class:
        'bg-n-ruby-9/15 text-n-ruby-11 dark:bg-n-ruby-9/25 dark:text-n-ruby-11',
    };
  }
  if (fr === 'stale') {
    return {
      text: t('PLAYER_PROFILE.PAYMENT_SCREENSHOTS.STATUS_STALE'),
      class:
        'bg-n-amber-9/15 text-n-amber-11 dark:bg-n-amber-9/25 dark:text-n-amber-11',
    };
  }
  if (entry.kind === 'deposit') {
    return {
      text: t('PLAYER_PROFILE.PAYMENT_SCREENSHOTS.STATUS_CONFIRMED'),
      class:
        'bg-n-teal-9/15 text-n-teal-11 dark:bg-n-teal-9/25 dark:text-n-teal-11',
    };
  }
  const kind = (entry.kind || '—').toString();
  return {
    text: kind ? kind.charAt(0).toUpperCase() + kind.slice(1) : '—',
    class: 'bg-n-alpha-2 text-n-slate-12',
  };
}

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
    <div
      v-if="financeLogsTotal > 0"
      :class="attrs.loyalty_tier ? 'mb-3 border-t border-n-weak pt-3' : 'mb-3'"
    >
      <div class="mb-2 flex items-start justify-between gap-2">
        <span class="text-xs font-semibold text-n-slate-12">
          {{ $t('PLAYER_PROFILE.PAYMENT_SCREENSHOTS.SECTION_TITLE') }}
        </span>
        <span class="shrink-0 text-[0.625rem] leading-tight text-n-slate-11">
          {{ $t('PLAYER_PROFILE.PAYMENT_SCREENSHOTS.CLICK_FULL') }}
        </span>
      </div>
      <div class="space-y-2">
        <div
          v-for="row in financeLogsVisibleRows"
          :key="financeRowDomKey(row)"
          class="flex gap-3 p-2"
          :class="
            isFinanceFlagged(row.entry)
              ? 'rounded-none border-l-2 border-l-[#E24B4A] bg-[rgba(226,75,74,0.04)]'
              : 'rounded-lg'
          "
        >
          <button
            type="button"
            class="relative h-[100px] w-[72px] shrink-0 cursor-pointer overflow-hidden rounded-md border-[0.5px] border-n-weak bg-n-solid-2 text-left outline-none ring-n-brand transition-shadow focus-visible:ring-2"
            :disabled="!(row.entry.image_thumb_url || row.entry.image_url)"
            @click="openFinanceFullImage(row.entry)"
          >
            <img
              v-if="!thumbErrored(row) && (row.entry.image_thumb_url || row.entry.image_url)"
              :src="row.entry.image_thumb_url || row.entry.image_url"
              alt=""
              class="h-full w-full object-cover"
              @error="onThumbError(row)"
            />
            <div
              v-else
              class="flex h-full w-full flex-col items-center justify-center gap-1 bg-n-solid-2 px-1 text-center"
            >
              <i class="i-lucide-image size-5 text-n-slate-11" />
              <span class="text-[0.625rem] font-medium leading-tight text-n-slate-11">
                {{ $t('PLAYER_PROFILE.PAYMENT_SCREENSHOTS.SCREENSHOT') }}
              </span>
            </div>
          </button>
          <div class="min-w-0 flex-1 space-y-1 text-xs text-n-slate-12">
            <div class="flex flex-wrap items-center gap-1.5">
              <span class="font-bold text-n-slate-12">
                {{ formatMoney(row.entry.amount) }}
              </span>
              <span
                v-if="row.entry.platform"
                class="rounded-full bg-n-alpha-2 px-2 py-0.5 text-[0.625rem] font-medium capitalize text-n-slate-12"
              >
                {{ row.entry.platform }}
              </span>
              <span
                class="rounded-full px-2 py-0.5 text-[0.625rem] font-medium"
                :class="financeStatusPill(row.entry).class"
              >
                {{ financeStatusPill(row.entry).text }}
              </span>
            </div>
            <div class="flex min-w-0 items-start gap-1 text-n-slate-11">
              <i class="i-lucide-arrow-right mt-0.5 size-3.5 shrink-0 text-n-slate-10" />
              <span class="min-w-0 break-words">
                <span>{{ $t('PLAYER_PROFILE.PAYMENT_SCREENSHOTS.FROM_PREFIX') }}</span>
                {{ ' ' }}
                <span class="text-n-slate-12">{{ financeSenderName(row.entry) }}</span>
                {{ ' → ' }}
                <span
                  :class="
                    row.entry.flag_reason === 'recipient_mismatch'
                      ? 'font-medium text-[#E24B4A]'
                      : 'text-n-slate-12'
                  "
                >{{ financeRecipientName(row.entry) }}</span>
              </span>
            </div>
            <div class="flex min-w-0 items-start gap-1">
              <i class="i-lucide-hash mt-0.5 size-3.5 shrink-0 text-n-slate-10" />
              <span class="min-w-0 break-all text-n-slate-12">
                {{ row.entry.transaction_id || '—' }}
                <span
                  v-if="row.sameTxAsAbove"
                  class="font-medium text-[#E24B4A]"
                >{{ $t('PLAYER_PROFILE.PAYMENT_SCREENSHOTS.SAME_AS_ABOVE') }}</span>
              </span>
            </div>
            <div class="flex items-start gap-1 text-n-slate-11">
              <i class="i-lucide-calendar mt-0.5 size-3.5 shrink-0 text-n-slate-10" />
              <span>
                <template v-if="row.entry.transaction_date || row.entry.transaction_time">
                  {{ row.entry.transaction_date || '' }}<template
                    v-if="row.entry.transaction_date && row.entry.transaction_time"
                  > · </template>{{ row.entry.transaction_time || '' }}
                </template>
                <template v-else>—</template>
              </span>
            </div>
            <div
              v-if="row.memoLine"
              class="flex min-w-0 items-start gap-1"
            >
              <i
                v-if="row.memoLine.type === 'memo'"
                class="i-lucide-message-square mt-0.5 size-3.5 shrink-0 text-n-slate-10"
              />
              <i
                v-else
                class="i-lucide-ban mt-0.5 size-3.5 shrink-0 text-n-slate-10"
              />
              <span class="min-w-0 break-words text-n-slate-12">{{
                row.memoLine.text
              }}</span>
            </div>
          </div>
        </div>
      </div>
      <Button
        v-if="financeLogsTotal > 5"
        class="mt-2 w-full"
        xs
        slate
        outline
        :label="
          financeLogsExpanded
            ? $t('PLAYER_PROFILE.PAYMENT_SCREENSHOTS.SHOW_RECENT')
            : $t('PLAYER_PROFILE.PAYMENT_SCREENSHOTS.VIEW_ALL', {
                count: financeLogsTotal,
              })
        "
        @click="financeLogsExpanded = !financeLogsExpanded"
      />
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
