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

defineOptions({
  name: 'PaymentHandlesSettings',
});

const { t } = useI18n();

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
const expandedDetailKey = ref(null);
const ledgerData = ref({});
const ledgerLoading = ref({});

const LEDGER_LABELS = {
  title: 'Payment ledger',
  export: 'Export CSV',
  score: 'Score',
  amount: 'Amount',
  sender: 'Sender',
  tag: 'Tag',
  note: 'Note',
  time: 'Time',
  status: 'Status',
  source: 'Source',
  view: 'View',
  sourceImage: 'Screenshot',
  sourceEmail: 'Email',
  screenshotPlaceholder: 'Payment screenshot preview',
  empty: 'No payment events yet.',
  ledgerToggle: 'Ledger',
};

const formatLedgerTime = raw => {
  if (!raw) return '—';
  try {
    const date = typeof raw === 'string' ? parseISO(raw) : new Date(raw);
    return format(date, 'MMM d, h:mm a');
  } catch {
    return '—';
  }
};

const mapLedgerEntry = (entry, index) => ({
  id: entry.transaction_id || entry.image_received_at || `ledger-${index}`,
  amount: entry.amount,
  score: entry.resolve_score ?? null,
  sender: entry.sender_name || entry.sender_handle || '—',
  tag: entry.recipient_handle || entry.sender_handle || '—',
  note: entry.note_or_memo || '—',
  time: formatLedgerTime(entry.image_received_at),
  status: entry.status || '—',
  source: entry.source === 'image_auto' ? 'Screenshot' : 'Email',
  sourceKey: entry.source === 'image_auto' ? 'image' : 'email',
  raw: entry,
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
  expandedDetailKey.value = null;
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

const detailKey = (eventId, rowType) => `${eventId}-${rowType}`;

const toggleDetail = (eventId, rowType) => {
  const key = detailKey(eventId, rowType);
  expandedDetailKey.value = expandedDetailKey.value === key ? null : key;
};

const isDetailOpen = (eventId, rowType) =>
  expandedDetailKey.value === detailKey(eventId, rowType);

const formatLedgerAmount = amount =>
  typeof amount === 'number' ? `$${amount.toFixed(0)}` : '—';

const scoreBarClass = score => {
  if (score == null) return 'bg-n-slate-4';
  if (score >= 75) return 'bg-[#6E56CF]';
  if (score >= 45) return 'bg-amber-500';
  return 'bg-red-500';
};

const scoreTextClass = score => {
  if (score == null) return 'text-n-slate-11';
  if (score >= 75) return 'text-[#4C3799] dark:text-[#DDD8F5]';
  if (score >= 45) return 'text-amber-700 dark:text-amber-300';
  return 'text-red-700 dark:text-red-300';
};

const ledgerStatusClass = status => {
  const normalized = String(status || '').toLowerCase();
  if (normalized === 'loaded') {
    return 'bg-green-500/15 text-green-700 dark:text-green-400 border border-green-500/30';
  }
  if (normalized === 'verifying') {
    return 'bg-amber-500/15 text-amber-800 dark:text-amber-300 border border-amber-500/30';
  }
  if (normalized === 'partial') {
    return 'bg-[#F0EDFF] text-[#4C3799] border border-[#DDD8F5]';
  }
  return 'bg-red-500/15 text-red-700 dark:text-red-400 border border-red-500/30';
};

const ledgerStatusLabel = status => {
  const normalized = String(status || '').toLowerCase();
  if (normalized === 'no email') return 'no email';
  if (normalized === 'mismatch') return 'mismatch';
  return normalized || '—';
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

onMounted(() => {
  loadHandles();
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

                  <div
                    v-else
                    class="overflow-x-auto rounded-xl border border-[#DDD8F5] bg-n-solid-1"
                  >
                    <table class="min-w-full text-xs">
                      <thead
                        class="border-b border-[#DDD8F5] bg-n-alpha-2 text-n-slate-11"
                      >
                        <tr>
                          <th class="px-3 py-2 text-left font-medium">
                            {{ LEDGER_LABELS.score }}
                          </th>
                          <th class="px-3 py-2 text-left font-medium">
                            {{ LEDGER_LABELS.amount }}
                          </th>
                          <th class="px-3 py-2 text-left font-medium">
                            {{ LEDGER_LABELS.sender }}
                          </th>
                          <th class="px-3 py-2 text-left font-medium">
                            {{ LEDGER_LABELS.tag }}
                          </th>
                          <th class="px-3 py-2 text-left font-medium">
                            {{ LEDGER_LABELS.note }}
                          </th>
                          <th class="px-3 py-2 text-left font-medium">
                            {{ LEDGER_LABELS.time }}
                          </th>
                          <th class="px-3 py-2 text-left font-medium">
                            {{ LEDGER_LABELS.status }}
                          </th>
                          <th class="px-3 py-2 text-left font-medium">
                            {{ LEDGER_LABELS.source }}
                          </th>
                          <th class="px-3 py-2 text-right font-medium" />
                        </tr>
                      </thead>
                      <tbody>
                        <template
                          v-for="event in getPaymentEvents(row)"
                          :key="event.id"
                        >
                          <tr
                            class="border-b border-[#DDD8F5]/70"
                            :class="
                              event.sourceKey === 'image'
                                ? 'bg-[#F0EDFF]/30 dark:bg-[#6E56CF]/5'
                                : 'bg-[#E6F7F2]/40 dark:bg-[#0F9B76]/5'
                            "
                          >
                            <td class="px-3 py-2 align-top">
                              <div class="flex items-center gap-2 min-w-[88px]">
                                <div
                                  class="h-1.5 w-14 overflow-hidden rounded-full bg-n-slate-4"
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
                              </div>
                            </td>
                            <td
                              class="px-3 py-2 align-top font-semibold text-n-slate-12"
                            >
                              {{ formatLedgerAmount(event.amount) }}
                            </td>
                            <td class="px-3 py-2 align-top text-n-slate-12">
                              {{ event.sender }}
                            </td>
                            <td
                              class="px-3 py-2 align-top font-mono text-n-slate-11"
                            >
                              {{ event.tag }}
                            </td>
                            <td class="px-3 py-2 align-top text-n-slate-11">
                              {{ event.note }}
                            </td>
                            <td
                              class="px-3 py-2 align-top whitespace-nowrap text-n-slate-11"
                            >
                              {{ event.time }}
                            </td>
                            <td class="px-3 py-2 align-top">
                              <span
                                class="inline-flex items-center rounded-full border px-2 py-0.5 text-[11px] font-medium capitalize"
                                :class="ledgerStatusClass(event.status)"
                              >
                                {{ ledgerStatusLabel(event.status) }}
                              </span>
                            </td>
                            <td class="px-3 py-2 align-top">
                              <span
                                class="inline-flex items-center rounded-full px-2 py-0.5 text-[11px] font-medium text-white"
                                :class="
                                  event.sourceKey === 'image'
                                    ? 'bg-[#6E56CF]'
                                    : 'bg-[#0F9B76]'
                                "
                              >
                                {{ event.source }}
                              </span>
                            </td>
                            <td class="px-3 py-2 align-top text-right">
                              <button
                                type="button"
                                class="rounded-md border px-2 py-1 text-[11px] font-medium transition-colors dark:bg-n-alpha-2"
                                :class="
                                  event.sourceKey === 'image'
                                    ? 'border-[#DDD8F5] bg-white text-[#6E56CF] hover:border-[#6E56CF] hover:bg-[#F0EDFF] hover:text-[#4C3799]'
                                    : 'border-[#0F9B76]/30 bg-white text-[#0F9B76] hover:border-[#0F9B76] hover:bg-[#E6F7F2]'
                                "
                                @click="toggleDetail(event.id, event.sourceKey)"
                              >
                                {{ LEDGER_LABELS.view }}
                              </button>
                            </td>
                          </tr>
                          <tr
                            v-if="isDetailOpen(event.id, event.sourceKey)"
                            class="border-b border-[#DDD8F5]/70 bg-n-alpha-2"
                          >
                            <td :colspan="9" class="px-3 py-3">
                              <div
                                v-if="
                                  event.sourceKey === 'image' &&
                                  event.raw?.image_url
                                "
                                class="rounded-lg border border-[#DDD8F5] bg-white p-4 dark:bg-n-alpha-2"
                              >
                                <img
                                  :src="event.raw.image_url"
                                  :alt="LEDGER_LABELS.screenshotPlaceholder"
                                  class="max-h-64 w-full rounded-lg object-contain"
                                />
                              </div>
                              <pre
                                v-else
                                class="m-0 overflow-x-auto rounded-lg border border-n-weak bg-n-alpha-2 p-3 text-[11px] leading-relaxed text-n-slate-12 whitespace-pre-wrap"
                              >
                                {{ JSON.stringify(event.raw, null, 2) }}
                              </pre>
                            </td>
                          </tr>
                        </template>
                      </tbody>
                    </table>
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
  </SettingsLayout>
</template>
