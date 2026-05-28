<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { dynamicTime } from 'shared/helpers/timeHelper';
import { format, parseISO } from 'date-fns';
import { picoSearch } from '@scmmishra/pico-search';

import Button from 'dashboard/components-next/button/Button.vue';
import {
  BaseTable,
  BaseTableRow,
  BaseTableCell,
} from 'dashboard/components-next/table';
import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import paymentHandlesApi from 'dashboard/api/paymentHandles';
import { useAccount } from 'dashboard/composables/useAccount';
import { useStore } from 'dashboard/composables/store';

defineOptions({
  name: 'PaymentHandlesSettings',
});

const { t } = useI18n();
const store = useStore();
const { currentAccount, updateAccount } = useAccount();

const DEFAULT_SCORING_CONFIG = {
  screenshot_present: 25,
  amount_match: 25,
  sender_match: 15,
  recipient_match: 10,
  txn_id_present: 10,
  email_confirmed: 10,
  time_proximity: 5,
  auto_load_threshold: 80,
  escalate_threshold: 40,
  decline_threshold: 39,
};

const SCORING_WEIGHT_FIELDS = [
  { key: 'screenshot_present', labelKey: 'PAYMENT_HANDLES.SCORING_SCREENSHOT' },
  { key: 'amount_match', labelKey: 'PAYMENT_HANDLES.SCORING_AMOUNT' },
  { key: 'sender_match', labelKey: 'PAYMENT_HANDLES.SCORING_SENDER' },
  { key: 'recipient_match', labelKey: 'PAYMENT_HANDLES.SCORING_RECIPIENT' },
  { key: 'txn_id_present', labelKey: 'PAYMENT_HANDLES.SCORING_TXN' },
  { key: 'email_confirmed', labelKey: 'PAYMENT_HANDLES.SCORING_EMAIL' },
  { key: 'time_proximity', labelKey: 'PAYMENT_HANDLES.SCORING_TIME' },
];

const SCORING_THRESHOLD_FIELDS = [
  {
    key: 'auto_load_threshold',
    labelKey: 'PAYMENT_HANDLES.SCORING_AUTO_LOAD',
    prefix: '≥',
    inputClass: 'border-green-500/40 focus:ring-green-500/30',
  },
  {
    key: 'escalate_threshold',
    labelKey: 'PAYMENT_HANDLES.SCORING_ESCALATE',
    prefix: '≥',
    inputClass: 'border-amber-500/40 focus:ring-amber-500/30',
  },
  {
    key: 'decline_threshold',
    labelKey: 'PAYMENT_HANDLES.SCORING_DECLINE',
    prefix: '<',
    inputClass: 'border-red-500/40 focus:ring-red-500/30',
  },
];

const scoringSettingsOpen = ref(false);
const scoringConfig = ref({ ...DEFAULT_SCORING_CONFIG });
const scoringSaving = ref(false);

const PLATFORMS = ['cashapp', 'chime', 'paypal', 'venmo', 'zelle'];
const STATUSES = ['active', 'failed', 'disabled'];

const IMAP_HOST_MAP = {
  'gmail.com': 'imap.gmail.com',
  'googlemail.com': 'imap.gmail.com',
  'outlook.com': 'outlook.office365.com',
  'hotmail.com': 'outlook.office365.com',
  'live.com': 'outlook.office365.com',
  'msn.com': 'outlook.office365.com',
  'yahoo.com': 'imap.mail.yahoo.com',
  'yahoo.co.uk': 'imap.mail.yahoo.com',
  'ymail.com': 'imap.mail.yahoo.com',
  'icloud.com': 'imap.mail.me.com',
  'me.com': 'imap.mail.me.com',
  'mac.com': 'imap.mail.me.com',
  'aol.com': 'imap.aol.com',
  'gmx.com': 'imap.gmx.com',
  'gmx.us': 'imap.gmx.com',
  'mail.com': 'imap.mail.com',
  'zoho.com': 'imap.zoho.com',
  'protonmail.com': '127.0.0.1',
  'pm.me': '127.0.0.1',
};

const IMAP_HOST_HINT =
  'Auto-detected from email. Override only if your provider uses a custom IMAP server.';

const handles = ref([]);
const isLoading = ref(true);
const searchQuery = ref('');
const showFormModal = ref(false);
const showDeleteModal = ref(false);
const formMode = ref('create');
const formSubmitting = ref(false);
const formErrors = ref([]);
const emailSectionOpen = ref(false);
const selectedRow = ref(null);
const editingId = ref(null);
const expandedLedgerId = ref(null);
const ledgerData = ref({});
const ledgerLoading = ref({});
const showScreenshotModal = ref(false);
const showEmailModal = ref(false);
const modalImageUrl = ref('');
const modalEmailContent = ref({});

const LEDGER_LABELS = {
  title: 'Payment ledger',
  export: 'Export CSV',
  score: 'Score',
  scoreBreakdown: 'Score Breakdown',
  scoreScreenshot: '📷 Screenshot',
  scoreAmountMatch: '💰 Amount match',
  scoreSenderMatch: '👤 Sender match',
  scoreTxnId: '🔢 Txn ID',
  scoreEmailConfirmed: '📧 Email confirmed',
  scoreTimeProximity: '⏱ Time proximity',
  sender: 'Sender',
  txnId: 'Txn ID',
  dateTime: 'Date & time',
  note: 'Notes',
  status: 'Status',
  sourceScreenshot: '📷 Screenshot',
  sourceEmail: '📧 Email',
  awaitingEmail: '⏳ Awaiting email confirmation',
  screenshotPlaceholder: 'Payment screenshot preview',
  empty: 'No payment events yet.',
  ledgerToggle: 'Ledger',
  emailFrom: 'From',
  emailSubject: 'Subject',
  matchCheck: '✓',
};

const formatLedgerTime = raw => {
  if (!raw) return '—';
  try {
    const date = typeof raw === 'string' ? parseISO(raw) : new Date(raw);
    return format(date, 'MMM d, yyyy h:mm a');
  } catch {
    return '—';
  }
};

const formatScreenshotDateTime = entry => {
  if (entry.image_received_at) return formatLedgerTime(entry.image_received_at);
  const parts = [entry.transaction_date, entry.transaction_time].filter(
    Boolean
  );
  return parts.length ? parts.join(' · ') : '—';
};

const formatScoreComponent = (value, max) => `${value ?? 0}/${max}`;

const mapLedgerEntry = (entry, index) => ({
  id: entry.transaction_id || entry.image_received_at || `ledger-${index}`,
  raw: entry,
  amount: entry.amount,
  platform: entry.platform,
  score: entry.confidence_score ?? entry.resolve_score ?? null,
  score_breakdown: entry.score_breakdown || null,
  status: entry.status || 'Screenshot Received',
  note: entry.note_or_memo || '—',
  headerTime: formatScreenshotDateTime(entry),
  screenshot: {
    sender:
      entry.sender_name || entry.sender_display || entry.sender_handle || '—',
    txnId: entry.transaction_id || '—',
    time: formatScreenshotDateTime(entry),
    note: entry.note_or_memo || '—',
    imageUrl: entry.image_url,
  },
  email: {
    sender: entry.email_sender_name || '—',
    subject: entry.email_subject || '—',
    date: formatLedgerTime(entry.email_date),
    note: entry.note_or_memo || '—',
    from: entry.email_from || '—',
    body: entry.email_body_snippet || '',
    confirmed: entry.email_confirmed === true,
  },
});

const form = ref({
  platform: 'cashapp',
  handle: '',
  display_name: '',
  priority: 1,
  status: 'active',
  notes: '',
  verification_email: '',
  verification_email_password: '',
  verification_email_host: '',
  verification_email_port: 993,
  verification_email_ssl: true,
});

const sortedHandles = computed(() =>
  [...handles.value].sort((a, b) => {
    if (a.platform !== b.platform) return a.platform.localeCompare(b.platform);
    return (a.priority || 0) - (b.priority || 0);
  })
);

const filteredRecords = computed(() => {
  const query = searchQuery.value.trim();
  if (!query) return sortedHandles.value;
  return picoSearch(sortedHandles.value, query, [
    'platform',
    'handle',
    'display_name',
    'status',
  ]);
});

const tableHeaders = computed(() => [
  t('PAYMENT_HANDLES.LIST.TABLE_HEADER.PLATFORM'),
  t('PAYMENT_HANDLES.LIST.TABLE_HEADER.HANDLE'),
  t('PAYMENT_HANDLES.LIST.TABLE_HEADER.DISPLAY_NAME'),
  t('PAYMENT_HANDLES.LIST.TABLE_HEADER.PRIORITY'),
  t('PAYMENT_HANDLES.LIST.TABLE_HEADER.STATUS'),
  t('PAYMENT_HANDLES.LIST.TABLE_HEADER.FAILURE_COUNT'),
  t('PAYMENT_HANDLES.LIST.TABLE_HEADER.LAST_FAILED'),
  t('PAYMENT_HANDLES.LIST.TABLE_HEADER.ACTIONS'),
]);

const deleteMessage = computed(() => ` ${selectedRow.value?.handle || ''}?`);

const platformLabel = id => {
  const key = `PAYMENT_HANDLES.PLATFORM_LABEL.${String(id || '').toUpperCase()}`;
  const out = t(key);
  return out === key ? id : out;
};

const statusLabel = status => {
  const key = `PAYMENT_HANDLES.STATUS.${String(status || '').toUpperCase()}`;
  const out = t(key);
  return out === key ? status : out;
};

const statusPillClass = status => {
  if (status === 'active') {
    return 'bg-green-500/15 text-green-700 dark:text-green-400 border border-green-500/30';
  }
  if (status === 'failed') {
    return 'bg-red-500/15 text-red-700 dark:text-red-400 border border-red-500/30';
  }
  return 'bg-n-slate-4 text-n-slate-11 border border-n-weak';
};

const getPaymentEvents = handle => ledgerData.value[handle.id] || [];

const isLedgerLoading = handleId => Boolean(ledgerLoading.value[handleId]);

const loadLedger = async handleId => {
  ledgerLoading.value = { ...ledgerLoading.value, [handleId]: true };
  try {
    const { data } = await paymentHandlesApi.ledger(handleId);
    const entries = Array.isArray(data) ? data : [];
    ledgerData.value = {
      ...ledgerData.value,
      [handleId]: entries.map(mapLedgerEntry),
    };
  } catch {
    useAlert(t('PAYMENT_HANDLES.ERROR_GENERIC'));
    ledgerData.value = { ...ledgerData.value, [handleId]: [] };
  } finally {
    ledgerLoading.value = { ...ledgerLoading.value, [handleId]: false };
  }
};

const toggleLedger = handleId => {
  if (expandedLedgerId.value === handleId) {
    expandedLedgerId.value = null;
    return;
  }

  expandedLedgerId.value = handleId;
  if (!ledgerData.value[handleId]) {
    loadLedger(handleId);
  }
};

const isLedgerOpen = handleId => expandedLedgerId.value === handleId;

const formatLedgerAmount = amount => {
  if (amount == null || amount === '') return '—';
  const num = Number(amount);
  if (Number.isNaN(num)) return '—';
  return `$${num % 1 === 0 ? num.toFixed(0) : num.toFixed(2)}`;
};

const platformBadgeClass = platform => {
  const p = String(platform || '').toLowerCase();
  if (p === 'paypal') return 'bg-blue-500/15 text-blue-700 border-blue-500/30';
  if (p === 'cashapp')
    return 'bg-green-500/15 text-green-700 border-green-500/30';
  if (p === 'venmo') return 'bg-sky-500/15 text-sky-700 border-sky-500/30';
  if (p === 'chime') return 'bg-teal-500/15 text-teal-700 border-teal-500/30';
  if (p === 'zelle')
    return 'bg-purple-500/15 text-purple-700 border-purple-500/30';
  return 'bg-n-slate-4 text-n-slate-11 border-n-weak';
};

const scoreBarClass = score => {
  if (score == null) return 'bg-n-slate-4';
  if (score >= 70) return 'bg-green-500';
  if (score >= 40) return 'bg-amber-500';
  return 'bg-red-500';
};

const scoreTextClass = score => {
  if (score == null) return 'text-n-slate-11';
  if (score >= 70) return 'text-green-700 dark:text-green-400';
  if (score >= 40) return 'text-amber-700 dark:text-amber-300';
  return 'text-red-700 dark:text-red-400';
};

const ledgerPaymentStatusClass = status => {
  const normalized = String(status || '').toLowerCase();
  if (normalized.includes('loaded')) {
    return 'bg-blue-500/15 text-blue-700 dark:text-blue-400 border border-blue-500/30';
  }
  if (normalized.includes('email verified')) {
    return 'bg-green-500/15 text-green-700 dark:text-green-400 border border-green-500/30';
  }
  if (normalized.includes('email received')) {
    return 'bg-purple-500/15 text-purple-700 dark:text-purple-400 border border-purple-500/30';
  }
  if (normalized.includes('screenshot received')) {
    return 'bg-amber-500/15 text-amber-800 dark:text-amber-300 border border-amber-500/30';
  }
  return 'bg-n-slate-4 text-n-slate-11 border border-n-weak';
};

const ledgerCardBorderClass = event => {
  const status = String(event.status || '').toLowerCase();
  if (status.includes('loaded')) return 'border-l-4 border-l-blue-500';
  if (status.includes('email verified')) return 'border-l-4 border-l-green-500';
  if (
    status.includes('email received') ||
    (event.email.confirmed && !event.screenshot.imageUrl)
  ) {
    return 'border-l-4 border-l-purple-500';
  }
  return 'border-l-4 border-l-amber-400';
};

const emailAmountMatches = event =>
  event.raw?.email_amount != null &&
  event.raw?.amount != null &&
  Number(event.raw.email_amount) === Number(event.raw.amount);

const emailSenderMatches = event => {
  const screenshotSender = String(event.raw?.sender_name || '')
    .toLowerCase()
    .trim();
  const emailSender = String(event.raw?.email_sender_name || '')
    .toLowerCase()
    .trim();
  if (!screenshotSender || !emailSender) return false;
  const first = screenshotSender.split(/\s+/)[0];
  return (
    emailSender.includes(first) ||
    screenshotSender.includes(emailSender.split(/\s+/)[0])
  );
};

const emailDateMatches = event => {
  if (!event.raw?.email_date || !event.raw?.image_received_at) return false;
  try {
    const emailTime = parseISO(event.raw.email_date);
    const imageTime = parseISO(event.raw.image_received_at);
    return Math.abs(emailTime - imageTime) < 30 * 60 * 1000;
  } catch {
    return false;
  }
};

const hasEmailRowData = event =>
  event.email.confirmed &&
  (event.email.sender !== '—' ||
    event.email.subject !== '—' ||
    event.email.body);

const openScreenshotModal = url => {
  if (!url) return;
  modalImageUrl.value = url;
  showScreenshotModal.value = true;
};

const openEmailModal = event => {
  modalEmailContent.value = {
    from: event.email.from,
    subject: event.email.subject,
    date: event.email.date,
    body: event.email.body,
  };
  showEmailModal.value = true;
};

const closeScreenshotModal = () => {
  showScreenshotModal.value = false;
  modalImageUrl.value = '';
};

const closeEmailModal = () => {
  showEmailModal.value = false;
  modalEmailContent.value = {};
};

const exportLedger = handle => {
  const events = getPaymentEvents(handle);
  const blob = new Blob([JSON.stringify(events, null, 2)], {
    type: 'application/json',
  });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = `payment-ledger-${handle.handle || handle.id}.json`;
  link.click();
  URL.revokeObjectURL(url);
};

const loadScoringConfig = () => {
  const saved =
    currentAccount.value?.custom_attributes?.payment_scoring_config || {};
  scoringConfig.value = {
    ...DEFAULT_SCORING_CONFIG,
    ...Object.fromEntries(
      Object.entries(saved).map(([key, value]) => [key, Number(value)])
    ),
  };
};

const saveScoringConfig = async () => {
  scoringSaving.value = true;
  try {
    const payment_scoring_config = Object.fromEntries(
      Object.entries(scoringConfig.value).map(([key, value]) => [
        key,
        Number(value),
      ])
    );
    await updateAccount({ custom_attributes: { payment_scoring_config } });
    useAlert(t('PAYMENT_HANDLES.SCORING_SAVED'));
  } catch {
    useAlert(t('PAYMENT_HANDLES.ERROR_GENERIC'));
  } finally {
    scoringSaving.value = false;
  }
};

const loadHandles = async () => {
  isLoading.value = true;
  try {
    const { data } = await paymentHandlesApi.get();
    handles.value = Array.isArray(data) ? data : [];
  } catch {
    useAlert(t('PAYMENT_HANDLES.ERROR_GENERIC'));
    handles.value = [];
  } finally {
    isLoading.value = false;
  }
};

const resetForm = () => {
  formErrors.value = [];
  form.value = {
    platform: 'cashapp',
    handle: '',
    display_name: '',
    priority: 1,
    status: 'active',
    notes: '',
    verification_email: '',
    verification_email_password: '',
    verification_email_host: '',
    verification_email_port: 993,
    verification_email_ssl: true,
  };
  emailSectionOpen.value = false;
};

const openCreate = () => {
  formMode.value = 'create';
  editingId.value = null;
  resetForm();
  showFormModal.value = true;
};

const hideFormModal = () => {
  showFormModal.value = false;
};

const openEdit = row => {
  formMode.value = 'edit';
  editingId.value = row.id;
  formErrors.value = [];
  form.value = {
    platform: row.platform,
    handle: row.handle,
    display_name: row.display_name || '',
    priority: row.priority,
    status: row.status,
    notes: row.notes || '',
    verification_email: row.verification_email || '',
    verification_email_password: '',
    verification_email_host: row.verification_email_host || '',
    verification_email_port: row.verification_email_port || 993,
    verification_email_ssl: row.verification_email_ssl !== false,
  };
  emailSectionOpen.value = Boolean(
    row.verification_email || row.verification_email_host
  );
  showFormModal.value = true;
};

const submitForm = async () => {
  formSubmitting.value = true;
  formErrors.value = [];
  try {
    const payload = {
      payment_handle: {
        platform: form.value.platform,
        handle: form.value.handle.trim(),
        display_name: form.value.display_name.trim(),
        priority: Number(form.value.priority),
        status: form.value.status,
        notes: form.value.notes,
        verification_email: form.value.verification_email || null,
        verification_email_host: form.value.verification_email_host || null,
        verification_email_port:
          Number(form.value.verification_email_port) || 993,
        verification_email_ssl: form.value.verification_email_ssl,
      },
    };
    if (form.value.verification_email_password.trim()) {
      payload.payment_handle.verification_email_password =
        form.value.verification_email_password;
    }

    if (formMode.value === 'create') {
      await paymentHandlesApi.create(payload);
      useAlert(t('PAYMENT_HANDLES.SUCCESS_CREATED'));
    } else {
      await paymentHandlesApi.update(editingId.value, payload);
      useAlert(t('PAYMENT_HANDLES.SUCCESS_UPDATED'));
    }
    hideFormModal();
    await loadHandles();
  } catch (e) {
    const errs = e?.response?.data?.errors;
    formErrors.value = Array.isArray(errs) ? errs : [];
    if (!formErrors.value.length) {
      useAlert(t('PAYMENT_HANDLES.ERROR_GENERIC'));
    }
  } finally {
    formSubmitting.value = false;
  }
};

const openDelete = row => {
  selectedRow.value = row;
  showDeleteModal.value = true;
};

const closeDelete = () => {
  showDeleteModal.value = false;
};

const confirmDelete = async () => {
  if (!selectedRow.value) return;
  try {
    await paymentHandlesApi.delete(selectedRow.value.id);
    useAlert(t('PAYMENT_HANDLES.SUCCESS_DELETED'));
    closeDelete();
    await loadHandles();
  } catch {
    useAlert(t('PAYMENT_HANDLES.ERROR_GENERIC'));
  }
};

const detectImapHostFromEmail = email => {
  const e = (email || '').toString().toLowerCase().trim();
  const at = e.indexOf('@');
  if (at < 0) return null;
  const domain = e.slice(at + 1);
  return IMAP_HOST_MAP[domain] || null;
};

watch(
  () => form.value.verification_email,
  newEmail => {
    const detected = detectImapHostFromEmail(newEmail);
    if (detected) {
      form.value.verification_email_host = detected;
    }
  }
);

onMounted(async () => {
  await store.dispatch('accounts/get', { silent: true });
  loadScoringConfig();
  loadHandles();
});

watch(currentAccount, () => {
  loadScoringConfig();
});
</script>

<template>
  <SettingsLayout
    :is-loading="isLoading"
    :loading-message="t('PAYMENT_HANDLES.LOADING')"
    :no-records-found="!handles.length"
    :no-records-message="t('PAYMENT_HANDLES.EMPTY')"
  >
    <template #header>
      <div
        class="mb-4 overflow-hidden rounded-xl border border-[#DDD8F5] bg-n-solid-1"
      >
        <button
          type="button"
          class="flex w-full items-center justify-between gap-3 px-4 py-3 text-left transition-colors hover:bg-[#F0EDFF]/40"
          @click="scoringSettingsOpen = !scoringSettingsOpen"
        >
          <span
            class="text-sm font-semibold text-[#4C3799] dark:text-[#DDD8F5]"
          >
            {{ t('PAYMENT_HANDLES.SCORING_TITLE') }}
          </span>
          <span
            class="i-lucide-chevron-down size-4 text-n-slate-11 transition-transform"
            :class="{ 'rotate-180': scoringSettingsOpen }"
          />
        </button>

        <div
          v-show="scoringSettingsOpen"
          class="border-t border-[#DDD8F5] px-4 py-4"
        >
          <div class="grid gap-6 lg:grid-cols-2">
            <div>
              <h3
                class="mb-3 text-xs font-semibold uppercase tracking-wide text-n-slate-11"
              >
                {{ t('PAYMENT_HANDLES.SCORING_WEIGHTS_TITLE') }}
              </h3>
              <div class="overflow-hidden rounded-lg border border-n-weak">
                <div
                  class="grid grid-cols-[1fr_5rem] gap-2 border-b border-n-weak bg-n-alpha-2 px-3 py-2 text-[11px] font-medium text-n-slate-11"
                >
                  <span>{{ t('PAYMENT_HANDLES.SCORING_WEIGHTS_TITLE') }}</span>
                  <span>{{ t('PAYMENT_HANDLES.SCORING_POINTS') }}</span>
                </div>
                <div
                  v-for="field in SCORING_WEIGHT_FIELDS"
                  :key="field.key"
                  class="grid grid-cols-[1fr_5rem] items-center gap-2 border-b border-n-weak/70 px-3 py-2 last:border-b-0"
                >
                  <span class="text-sm text-n-slate-12">{{
                    t(field.labelKey)
                  }}</span>
                  <input
                    v-model.number="scoringConfig[field.key]"
                    type="number"
                    min="0"
                    max="100"
                    class="h-8 w-full rounded-md border border-n-weak bg-n-alpha-3 px-2 text-sm text-n-slate-12"
                  />
                </div>
              </div>
            </div>

            <div>
              <h3
                class="mb-3 text-xs font-semibold uppercase tracking-wide text-n-slate-11"
              >
                {{ t('PAYMENT_HANDLES.SCORING_THRESHOLDS_TITLE') }}
              </h3>
              <div class="overflow-hidden rounded-lg border border-n-weak">
                <div
                  class="grid grid-cols-[1fr_5rem] gap-2 border-b border-n-weak bg-n-alpha-2 px-3 py-2 text-[11px] font-medium text-n-slate-11"
                >
                  <span>{{
                    t('PAYMENT_HANDLES.SCORING_THRESHOLDS_TITLE')
                  }}</span>
                  <span>{{ t('PAYMENT_HANDLES.SCORING_THRESHOLD') }}</span>
                </div>
                <div
                  v-for="field in SCORING_THRESHOLD_FIELDS"
                  :key="field.key"
                  class="grid grid-cols-[1fr_5rem] items-center gap-2 border-b border-n-weak/70 px-3 py-2 last:border-b-0"
                >
                  <span class="text-sm text-n-slate-12">
                    {{ field.prefix }}
                    {{ t(field.labelKey) }}
                  </span>
                  <input
                    v-model.number="scoringConfig[field.key]"
                    type="number"
                    min="0"
                    max="100"
                    class="h-8 w-full rounded-md border bg-n-alpha-3 px-2 text-sm text-n-slate-12"
                    :class="field.inputClass"
                  />
                </div>
              </div>
            </div>
          </div>

          <div class="mt-4 flex justify-end">
            <Button
              :label="t('PAYMENT_HANDLES.SCORING_SAVE')"
              size="sm"
              color="blue"
              :is-loading="scoringSaving"
              @click="saveScoringConfig"
            />
          </div>
        </div>
      </div>

      <BaseSettingsHeader
        v-model:search-query="searchQuery"
        :title="t('PAYMENT_HANDLES.TITLE')"
        :description="t('PAYMENT_HANDLES.DESCRIPTION')"
        feature-name="payment_handles"
        :search-placeholder="t('PAYMENT_HANDLES.SEARCH_PLACEHOLDER')"
        :back-button-label="$t('SIDEBAR.INTEGRATIONS')"
      >
        <template v-if="handles.length" #count>
          <span class="text-body-main text-n-slate-11">
            {{ handles.length }}
          </span>
        </template>
        <template #actions>
          <Button
            :label="t('PAYMENT_HANDLES.ADD_BUTTON')"
            size="sm"
            @click="openCreate"
          />
        </template>
      </BaseSettingsHeader>
    </template>

    <template #body>
      <BaseTable
        :headers="tableHeaders"
        :items="filteredRecords"
        :no-data-message="
          !handles.length
            ? t('PAYMENT_HANDLES.EMPTY')
            : searchQuery
              ? t('PAYMENT_HANDLES.NO_RESULTS')
              : ''
        "
      >
        <template #row="{ items }">
          <template v-for="row in items" :key="row.id">
            <BaseTableRow :item="row">
              <template #default>
                <BaseTableCell>
                  <span class="text-body-main text-n-slate-12">
                    {{ platformLabel(row.platform) }}
                  </span>
                </BaseTableCell>
                <BaseTableCell>
                  <span class="text-body-main text-n-slate-12 font-medium">
                    {{ row.handle }}
                  </span>
                </BaseTableCell>
                <BaseTableCell>
                  <span class="text-body-main text-n-slate-11">
                    {{ row.display_name || '-' }}
                  </span>
                </BaseTableCell>
                <BaseTableCell>
                  <span class="text-body-main text-n-slate-11">
                    {{ row.priority }}
                  </span>
                </BaseTableCell>
                <BaseTableCell>
                  <span
                    class="inline-flex items-center px-2 py-0.5 text-xs font-medium rounded-full"
                    :class="statusPillClass(row.status)"
                  >
                    {{ statusLabel(row.status) }}
                  </span>
                </BaseTableCell>
                <BaseTableCell>
                  <span class="text-body-main text-n-slate-11">
                    {{ row.failure_count ?? 0 }}
                  </span>
                </BaseTableCell>
                <BaseTableCell>
                  <span class="text-body-main text-n-slate-11 text-sm">
                    {{
                      row.last_failure_at
                        ? dynamicTime(row.last_failure_at)
                        : '-'
                    }}
                  </span>
                </BaseTableCell>
                <BaseTableCell align="end">
                  <div class="flex gap-2 justify-end flex-shrink-0">
                    <Button
                      v-tooltip.top="LEDGER_LABELS.ledgerToggle"
                      :label="LEDGER_LABELS.ledgerToggle"
                      slate
                      sm
                      class="!text-[#6E56CF] hover:enabled:!bg-[#F0EDFF] hover:enabled:!text-[#4C3799]"
                      :class="{
                        '!bg-[#F0EDFF] !text-[#4C3799] ring-1 ring-[#DDD8F5]':
                          isLedgerOpen(row.id),
                      }"
                      @click="toggleLedger(row.id)"
                    />
                    <Button
                      v-tooltip.top="t('PAYMENT_HANDLES.EDIT')"
                      icon="i-woot-edit-pen"
                      slate
                      sm
                      @click="openEdit(row)"
                    />
                    <Button
                      v-tooltip.top="t('PAYMENT_HANDLES.DELETE')"
                      icon="i-woot-bin"
                      slate
                      sm
                      class="hover:enabled:text-n-ruby-11 hover:enabled:bg-n-ruby-2"
                      @click="openDelete(row)"
                    />
                  </div>
                </BaseTableCell>
              </template>
            </BaseTableRow>
            <tr v-if="isLedgerOpen(row.id)">
              <td
                :colspan="tableHeaders.length"
                class="p-0 border-t border-[#DDD8F5]"
              >
                <div class="bg-[#F0EDFF]/40 dark:bg-n-alpha-2 px-4 py-4">
                  <div
                    class="flex flex-wrap items-center justify-between gap-3 mb-4"
                  >
                    <div>
                      <h3
                        class="m-0 text-sm font-semibold text-[#4C3799] dark:text-[#DDD8F5]"
                      >
                        {{ LEDGER_LABELS.title }}
                      </h3>
                      <p class="m-0 mt-1 text-xs text-n-slate-11">
                        {{ platformLabel(row.platform) }} · {{ row.handle }}
                      </p>
                    </div>
                    <button
                      type="button"
                      class="inline-flex items-center gap-1.5 rounded-lg border border-[#6E56CF] bg-[#6E56CF] px-3 py-1.5 text-xs font-medium text-white transition-colors hover:bg-[#4C3799] hover:border-[#4C3799]"
                      @click="exportLedger(row)"
                    >
                      {{ LEDGER_LABELS.export }}
                    </button>
                  </div>

                  <div
                    v-if="isLedgerLoading(row.id)"
                    class="rounded-lg border border-[#DDD8F5] bg-n-solid-1 px-4 py-8 text-center text-sm text-n-slate-11"
                  >
                    <span class="inline-flex items-center gap-2">
                      <span
                        class="i-lucide-loader-circle size-4 animate-spin text-[#6E56CF]"
                      />
                      {{ t('PAYMENT_HANDLES.LOADING') }}
                    </span>
                  </div>

                  <div
                    v-else-if="!getPaymentEvents(row).length"
                    class="rounded-lg border border-[#DDD8F5] bg-n-solid-1 px-4 py-8 text-center text-sm text-n-slate-11"
                  >
                    {{ LEDGER_LABELS.empty }}
                  </div>

                  <div v-else class="flex flex-col gap-3">
                    <article
                      v-for="event in getPaymentEvents(row)"
                      :key="event.id"
                      class="overflow-hidden rounded-xl border border-[#DDD8F5] bg-n-solid-1"
                      :class="ledgerCardBorderClass(event)"
                    >
                      <!-- Card header -->
                      <div
                        class="flex flex-wrap items-center justify-between gap-3 border-b border-[#DDD8F5] bg-n-alpha-2 px-4 py-3"
                      >
                        <div class="flex flex-wrap items-center gap-3">
                          <span
                            class="text-xl font-bold tabular-nums text-n-slate-12"
                          >
                            {{ formatLedgerAmount(event.amount) }}
                          </span>
                          <span
                            class="inline-flex items-center rounded-full border px-2.5 py-0.5 text-xs font-medium capitalize"
                            :class="platformBadgeClass(event.platform)"
                          >
                            {{ platformLabel(event.platform) }}
                          </span>
                          <span class="text-xs text-n-slate-11">
                            {{ event.headerTime }}
                          </span>
                        </div>
                        <div class="flex flex-wrap items-center gap-3">
                          <div
                            class="relative group flex items-center gap-2 min-w-[100px]"
                          >
                            <span
                              class="text-[11px] font-medium text-n-slate-11"
                            >
                              {{ LEDGER_LABELS.score }}
                            </span>
                            <div
                              class="h-1.5 w-16 overflow-hidden rounded-full bg-n-slate-4"
                            >
                              <div
                                v-if="event.score != null"
                                class="h-full rounded-full"
                                :class="scoreBarClass(event.score)"
                                :style="{ width: `${event.score}%` }"
                              />
                            </div>
                            <span
                              class="text-xs font-semibold tabular-nums"
                              :class="scoreTextClass(event.score)"
                            >
                              {{ event.score ?? '—' }}
                            </span>
                            <div
                              v-if="event.score_breakdown"
                              class="absolute z-10 hidden group-hover:block right-0 top-full mt-1 w-56 rounded-lg border border-n-weak bg-n-solid-1 p-3 shadow-lg text-xs"
                            >
                              <div class="font-semibold mb-2">
                                {{ LEDGER_LABELS.scoreBreakdown }}
                              </div>
                              <div class="flex justify-between mb-1">
                                <span>{{ LEDGER_LABELS.scoreScreenshot }}</span>
                                <span
                                  :class="
                                    event.score_breakdown.screenshot > 0
                                      ? 'text-green-600 font-semibold'
                                      : 'text-n-slate-10'
                                  "
                                >
                                  {{
                                    formatScoreComponent(
                                      event.score_breakdown.screenshot,
                                      30
                                    )
                                  }}
                                </span>
                              </div>
                              <div class="flex justify-between mb-1">
                                <span>{{
                                  LEDGER_LABELS.scoreAmountMatch
                                }}</span>
                                <span
                                  :class="
                                    event.score_breakdown.amount_match > 0
                                      ? 'text-green-600 font-semibold'
                                      : 'text-n-slate-10'
                                  "
                                >
                                  {{
                                    formatScoreComponent(
                                      event.score_breakdown.amount_match,
                                      25
                                    )
                                  }}
                                </span>
                              </div>
                              <div class="flex justify-between mb-1">
                                <span>{{
                                  LEDGER_LABELS.scoreSenderMatch
                                }}</span>
                                <span
                                  :class="
                                    event.score_breakdown.sender_match > 0
                                      ? 'text-green-600 font-semibold'
                                      : 'text-n-slate-10'
                                  "
                                >
                                  {{
                                    formatScoreComponent(
                                      event.score_breakdown.sender_match,
                                      15
                                    )
                                  }}
                                </span>
                              </div>
                              <div class="flex justify-between mb-1">
                                <span>{{ LEDGER_LABELS.scoreTxnId }}</span>
                                <span
                                  :class="
                                    event.score_breakdown.txn_id > 0
                                      ? 'text-green-600 font-semibold'
                                      : 'text-n-slate-10'
                                  "
                                >
                                  {{
                                    formatScoreComponent(
                                      event.score_breakdown.txn_id,
                                      15
                                    )
                                  }}
                                </span>
                              </div>
                              <div class="flex justify-between mb-1">
                                <span>{{
                                  LEDGER_LABELS.scoreEmailConfirmed
                                }}</span>
                                <span
                                  :class="
                                    event.score_breakdown.email_confirmed > 0
                                      ? 'text-green-600 font-semibold'
                                      : 'text-n-slate-10'
                                  "
                                >
                                  {{
                                    formatScoreComponent(
                                      event.score_breakdown.email_confirmed,
                                      10
                                    )
                                  }}
                                </span>
                              </div>
                              <div class="flex justify-between">
                                <span>{{
                                  LEDGER_LABELS.scoreTimeProximity
                                }}</span>
                                <span
                                  :class="
                                    event.score_breakdown.time_proximity > 0
                                      ? 'text-green-600 font-semibold'
                                      : 'text-n-slate-10'
                                  "
                                >
                                  {{
                                    formatScoreComponent(
                                      event.score_breakdown.time_proximity,
                                      5
                                    )
                                  }}
                                </span>
                              </div>
                            </div>
                          </div>
                          <span
                            class="inline-flex items-center rounded-full border px-2.5 py-0.5 text-[11px] font-medium"
                            :class="ledgerPaymentStatusClass(event.status)"
                          >
                            {{ event.status }}
                          </span>
                        </div>
                      </div>

                      <!-- Screenshot row -->
                      <div
                        class="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1 border-b border-[#DDD8F5]/70 bg-[#F0EDFF]/20 px-4 py-3 text-xs dark:bg-[#6E56CF]/5"
                      >
                        <button
                          type="button"
                          class="col-span-2 mb-1 inline-flex w-fit items-center rounded-full border border-[#6E56CF]/30 bg-[#F0EDFF] px-2.5 py-0.5 text-[11px] font-medium text-[#4C3799] transition-colors hover:border-[#6E56CF] hover:bg-[#6E56CF]/10 disabled:cursor-not-allowed disabled:opacity-50"
                          :disabled="!event.screenshot.imageUrl"
                          @click="
                            openScreenshotModal(event.screenshot.imageUrl)
                          "
                        >
                          {{ LEDGER_LABELS.sourceScreenshot }}
                        </button>
                        <span class="text-n-slate-11">{{
                          LEDGER_LABELS.sender
                        }}</span>
                        <span class="font-medium text-n-slate-12">
                          {{ event.screenshot.sender }}
                        </span>
                        <span class="text-n-slate-11">{{
                          LEDGER_LABELS.txnId
                        }}</span>
                        <span class="font-mono text-n-slate-11">
                          {{ event.screenshot.txnId }}
                        </span>
                        <span class="text-n-slate-11">{{
                          LEDGER_LABELS.dateTime
                        }}</span>
                        <span class="text-n-slate-11">{{
                          event.screenshot.time
                        }}</span>
                        <span class="text-n-slate-11">{{
                          LEDGER_LABELS.note
                        }}</span>
                        <span class="text-n-slate-11">{{
                          event.screenshot.note
                        }}</span>
                      </div>

                      <!-- Email row -->
                      <div
                        v-if="hasEmailRowData(event)"
                        class="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1 px-4 py-3 text-xs bg-[#E6F7F2]/20 dark:bg-[#0F9B76]/5"
                      >
                        <button
                          type="button"
                          class="col-span-2 mb-1 inline-flex w-fit items-center rounded-full border border-[#0F9B76]/30 bg-[#E6F7F2] px-2.5 py-0.5 text-[11px] font-medium text-[#0F9B76] transition-colors hover:border-[#0F9B76] hover:bg-[#0F9B76]/10"
                          @click="openEmailModal(event)"
                        >
                          {{ LEDGER_LABELS.sourceEmail }}
                        </button>
                        <span class="text-n-slate-11">{{
                          LEDGER_LABELS.sender
                        }}</span>
                        <span class="font-medium text-n-slate-12">
                          {{ event.email.sender }}
                          <span
                            v-if="emailSenderMatches(event)"
                            class="ml-1 text-green-600"
                          >
                            {{ LEDGER_LABELS.matchCheck }}
                          </span>
                        </span>
                        <span class="text-n-slate-11">{{
                          LEDGER_LABELS.emailSubject
                        }}</span>
                        <span class="text-n-slate-11">{{
                          event.email.subject
                        }}</span>
                        <span class="text-n-slate-11">{{
                          LEDGER_LABELS.dateTime
                        }}</span>
                        <span class="text-n-slate-11">
                          {{ event.email.date }}
                          <span
                            v-if="emailDateMatches(event)"
                            class="ml-1 text-green-600"
                          >
                            {{ LEDGER_LABELS.matchCheck }}
                          </span>
                        </span>
                        <span class="text-n-slate-11">{{
                          LEDGER_LABELS.note
                        }}</span>
                        <span class="text-n-slate-11">
                          {{ event.email.note }}
                          <span
                            v-if="emailAmountMatches(event)"
                            class="ml-1 text-green-600"
                          >
                            {{ LEDGER_LABELS.matchCheck }}
                          </span>
                        </span>
                      </div>
                      <div
                        v-else
                        class="px-4 py-3 text-xs text-n-slate-11 bg-n-alpha-2"
                      >
                        {{ LEDGER_LABELS.awaitingEmail }}
                      </div>
                    </article>
                  </div>
                </div>
              </td>
            </tr>
          </template>
        </template>
      </BaseTable>
    </template>

    <woot-modal v-model:show="showFormModal" :on-close="hideFormModal">
      <div class="flex flex-col h-auto overflow-auto">
        <woot-modal-header
          :header-title="
            formMode === 'create'
              ? t('PAYMENT_HANDLES.MODAL.ADD_TITLE')
              : t('PAYMENT_HANDLES.MODAL.EDIT_TITLE')
          "
          :header-content="
            formMode === 'create'
              ? t('PAYMENT_HANDLES.MODAL.ADD_DESC')
              : t('PAYMENT_HANDLES.MODAL.EDIT_DESC')
          "
        />
        <form
          class="flex flex-col gap-4 px-0 pb-2"
          @submit.prevent="submitForm"
        >
          <div
            v-if="formErrors.length"
            class="p-3 text-sm rounded-lg border text-n-ruby-11 bg-n-ruby-2 border-n-ruby-7"
            role="alert"
          >
            <p class="m-0 mb-1 font-medium">
              {{ t('PAYMENT_HANDLES.VALIDATION_ERROR_PREFIX') }}
            </p>
            <ul class="pl-4 m-0 list-disc">
              <li v-for="(err, idx) in formErrors" :key="idx">
                {{ err }}
              </li>
            </ul>
          </div>

          <div class="grid gap-4 sm:grid-cols-2">
            <label class="flex flex-col gap-1 text-sm">
              <span class="text-n-slate-11">{{
                t('PAYMENT_HANDLES.FORM.PLATFORM')
              }}</span>
              <select
                v-model="form.platform"
                :disabled="formMode === 'edit'"
                class="h-10 px-3 text-sm rounded-lg border bg-n-alpha-3 border-n-weak text-n-slate-12"
              >
                <option v-for="p in PLATFORMS" :key="p" :value="p">
                  {{ platformLabel(p) }}
                </option>
              </select>
            </label>
            <label class="flex flex-col gap-1 text-sm">
              <span class="text-n-slate-11">{{
                t('PAYMENT_HANDLES.FORM.STATUS')
              }}</span>
              <select
                v-model="form.status"
                class="h-10 px-3 text-sm rounded-lg border bg-n-alpha-3 border-n-weak text-n-slate-12"
              >
                <option v-for="s in STATUSES" :key="s" :value="s">
                  {{ statusLabel(s) }}
                </option>
              </select>
            </label>
          </div>

          <woot-input
            v-model="form.handle"
            class="w-full"
            :label="t('PAYMENT_HANDLES.FORM.HANDLE')"
            :placeholder="t('PAYMENT_HANDLES.FORM.HANDLE_PLACEHOLDER')"
            data-testid="payment-handle-handle"
          />
          <woot-input
            v-model="form.display_name"
            class="w-full"
            :label="t('PAYMENT_HANDLES.FORM.DISPLAY_NAME')"
            :placeholder="t('PAYMENT_HANDLES.FORM.DISPLAY_NAME_PLACEHOLDER')"
            data-testid="payment-handle-display-name"
          />
          <woot-input
            v-model.number="form.priority"
            class="w-full"
            type="number"
            :label="t('PAYMENT_HANDLES.FORM.PRIORITY')"
            data-testid="payment-handle-priority"
          />

          <label class="flex flex-col gap-1 text-sm">
            <span class="text-n-slate-11">{{
              t('PAYMENT_HANDLES.FORM.NOTES')
            }}</span>
            <textarea
              v-model="form.notes"
              rows="3"
              class="px-3 py-2 text-sm rounded-lg border resize-y bg-n-alpha-3 border-n-weak text-n-slate-12"
            />
          </label>

          <button
            type="button"
            class="flex gap-2 items-center px-0 py-2 text-sm font-medium text-left border-0 bg-transparent text-woot-500"
            @click="emailSectionOpen = !emailSectionOpen"
          >
            <span
              class="transition-transform i-lucide-chevron-down size-4"
              :class="{ 'rotate-180': emailSectionOpen }"
            />
            {{ t('PAYMENT_HANDLES.FORM.VERIFICATION_SECTION') }}
          </button>
          <div
            v-show="emailSectionOpen"
            class="grid gap-4 p-4 rounded-xl border border-n-weak bg-n-alpha-2"
          >
            <woot-input
              v-model="form.verification_email"
              class="w-full"
              type="email"
              :label="t('PAYMENT_HANDLES.FORM.VERIFICATION_EMAIL')"
              placeholder="your.account@gmail.com (host auto-fills)"
            />
            <woot-input
              v-model="form.verification_email_password"
              class="w-full"
              type="password"
              autocomplete="new-password"
              :label="t('PAYMENT_HANDLES.FORM.VERIFICATION_PASSWORD')"
              :placeholder="
                formMode === 'edit'
                  ? t('PAYMENT_HANDLES.FORM.PASSWORD_PLACEHOLDER')
                  : ''
              "
            />
            <div class="grid gap-4 sm:grid-cols-2">
              <div class="flex flex-col gap-1">
                <woot-input
                  v-model="form.verification_email_host"
                  class="w-full"
                  :label="t('PAYMENT_HANDLES.FORM.VERIFICATION_HOST')"
                />
                <p class="m-0 text-xs text-n-slate-11">
                  {{ IMAP_HOST_HINT }}
                </p>
              </div>
              <woot-input
                v-model.number="form.verification_email_port"
                class="w-full"
                type="number"
                :label="t('PAYMENT_HANDLES.FORM.VERIFICATION_PORT')"
              />
            </div>
            <label
              class="inline-flex gap-2 items-center text-sm cursor-pointer select-none"
            >
              <input
                v-model="form.verification_email_ssl"
                type="checkbox"
                class="rounded border-n-weak"
              />
              <span>{{ t('PAYMENT_HANDLES.FORM.VERIFICATION_SSL') }}</span>
            </label>
          </div>

          <div class="flex gap-2 justify-end pt-2">
            <Button
              faded
              slate
              type="button"
              :label="t('PAYMENT_HANDLES.CANCEL')"
              @click="hideFormModal"
            />
            <Button
              type="submit"
              color="blue"
              :label="t('PAYMENT_HANDLES.SAVE')"
              :is-loading="formSubmitting"
            />
          </div>
        </form>
      </div>
    </woot-modal>

    <woot-delete-modal
      v-model:show="showDeleteModal"
      :on-close="closeDelete"
      :on-confirm="confirmDelete"
      :title="t('PAYMENT_HANDLES.DELETE_CONFIRM.TITLE')"
      :message="t('PAYMENT_HANDLES.DELETE_CONFIRM.MESSAGE')"
      :message-value="deleteMessage"
      :confirm-text="t('PAYMENT_HANDLES.DELETE_CONFIRM.YES')"
      :reject-text="t('PAYMENT_HANDLES.DELETE_CONFIRM.NO')"
    />

    <woot-modal
      v-model:show="showScreenshotModal"
      :on-close="closeScreenshotModal"
    >
      <div class="p-4">
        <img
          v-if="modalImageUrl"
          :src="modalImageUrl"
          :alt="LEDGER_LABELS.screenshotPlaceholder"
          class="max-h-[70vh] w-full rounded-lg object-contain"
        />
      </div>
    </woot-modal>

    <woot-modal v-model:show="showEmailModal" :on-close="closeEmailModal">
      <div class="flex flex-col gap-3 p-4 text-sm">
        <div>
          <span class="text-n-slate-11">{{ LEDGER_LABELS.emailFrom }}: </span>
          <span class="text-n-slate-12">{{
            modalEmailContent.from || '—'
          }}</span>
        </div>
        <div>
          <span class="text-n-slate-11">
            {{ LEDGER_LABELS.emailSubject }}:
          </span>
          <span class="text-n-slate-12">{{
            modalEmailContent.subject || '—'
          }}</span>
        </div>
        <div>
          <span class="text-n-slate-11">{{ LEDGER_LABELS.dateTime }}: </span>
          <span class="text-n-slate-12">{{
            modalEmailContent.date || '—'
          }}</span>
        </div>
        <pre
          class="m-0 max-h-64 overflow-auto rounded-lg border border-n-weak bg-n-alpha-2 p-3 text-xs leading-relaxed text-n-slate-12 whitespace-pre-wrap"
        >
          {{ modalEmailContent.body || '—' }}
        </pre>
      </div>
    </woot-modal>
  </SettingsLayout>
</template>
