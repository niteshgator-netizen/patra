<script setup>
import { ref, computed, onMounted, onUnmounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { dynamicTime } from 'shared/helpers/timeHelper';

import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import paymentHandlesApi from 'dashboard/api/paymentHandles';

const { t } = useI18n();

const PLATFORMS = [
  { id: 'cashapp', label: 'Cash App', max: 3 },
  { id: 'chime', label: 'Chime', max: 3 },
  { id: 'venmo', label: 'Venmo', max: 2 },
  { id: 'paypal', label: 'PayPal', max: 3 },
  { id: 'varo', label: 'Varo', max: 1 },
  { id: 'zelle', label: 'Zelle', max: 1 },
  { id: 'boltpay', label: 'BoltPay', max: 1 },
  { id: 'applepay', label: 'Apple Pay', max: 1 },
  { id: 'usdt', label: 'USDT', max: 1 },
];

const handles = ref([]);
const isLoading = ref(true);
const selectedPlatform = ref('cashapp');
const emailSectionOpen = ref(false);

const formDialog = ref(null);
const deleteDialog = ref(null);
const formMode = ref('create');
const editingId = ref(null);
const formSubmitting = ref(false);
const deleteTarget = ref(null);

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

const nowTick = ref(Date.now());
let refreshTimer;

const platformMeta = id => PLATFORMS.find(p => p.id === id) || PLATFORMS[0];

const handlesForPlatform = computed(() =>
  handles.value
    .filter(h => h.platform === selectedPlatform.value)
    .sort((a, b) => (a.priority || 0) - (b.priority || 0))
);

const usableForSelected = computed(() =>
  handlesForPlatform.value.filter(
    h =>
      h.status === 'active' &&
      (!h.cooldown_until || new Date(h.cooldown_until) <= new Date(nowTick.value))
  )
);

const allDownForSelected = computed(
  () => handlesForPlatform.value.length > 0 && usableForSelected.value.length === 0
);

const maxForSelected = computed(() => platformMeta(selectedPlatform.value).max);

const tabBadge = plat =>
  t('PAYMENT_HANDLES.TAB_COUNT', {
    current: handles.value.filter(h => h.platform === plat.id).length,
    max: plat.max,
  });

const statusClass = status => {
  const map = {
    active: 'bg-green-500/15 text-green-700 dark:text-green-400 border border-green-500/30',
    limited: 'bg-amber-500/15 text-amber-800 dark:text-amber-300 border border-amber-500/30',
    frozen: 'bg-red-500/15 text-red-700 dark:text-red-400 border border-red-500/30',
    cooldown: 'bg-n-slate-4 text-n-slate-11 border border-n-weak',
    disabled: 'bg-n-slate-4 text-n-slate-11 border border-n-weak',
  };
  return map[status] || map.disabled;
};

const statusLabel = status => {
  const key = `PAYMENT_HANDLES.STATUS_${String(status || '').toUpperCase()}`;
  const translated = t(key);
  return translated === key ? status : translated;
};

const displayHandle = row => {
  const h = (row.handle || '').trim();
  if (!h) return '';
  if (h.startsWith('$') || h.startsWith('@')) return h;
  if (row.platform === 'cashapp') return `$${h}`;
  return `@${h}`;
};

const applyImapPreset = email => {
  const domain = email.split('@')[1]?.toLowerCase().trim();
  const presets = {
    'gmail.com': { host: 'imap.gmail.com', port: 993, ssl: true },
    'googlemail.com': { host: 'imap.gmail.com', port: 993, ssl: true },
    'outlook.com': { host: 'outlook.office365.com', port: 993, ssl: true },
    'hotmail.com': { host: 'outlook.office365.com', port: 993, ssl: true },
    'live.com': { host: 'outlook.office365.com', port: 993, ssl: true },
    'yahoo.com': { host: 'imap.mail.yahoo.com', port: 993, ssl: true },
  };
  const p = presets[domain];
  if (p) {
    form.value.verification_email_host = p.host;
    form.value.verification_email_port = p.port;
    form.value.verification_email_ssl = p.ssl;
  }
};

const loadHandles = async () => {
  isLoading.value = true;
  try {
    const { data } = await paymentHandlesApi.list();
    handles.value = Array.isArray(data) ? data : [];
  } catch {
    useAlert(t('PAYMENT_HANDLES.ERROR_GENERIC'));
    handles.value = [];
  } finally {
    isLoading.value = false;
  }
};

const openCreate = () => {
  formMode.value = 'create';
  editingId.value = null;
  form.value = {
    platform: selectedPlatform.value,
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
  formDialog.value?.open();
};

const openEdit = row => {
  formMode.value = 'edit';
  editingId.value = row.id;
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
  formDialog.value?.open();
};

const submitForm = async () => {
  formSubmitting.value = true;
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
        verification_email_port: Number(form.value.verification_email_port) || 993,
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
    formDialog.value?.close();
    await loadHandles();
  } catch (e) {
    const msg = e?.response?.data?.errors?.join?.(', ') || t('PAYMENT_HANDLES.ERROR_GENERIC');
    useAlert(msg);
  } finally {
    formSubmitting.value = false;
  }
};

const confirmDelete = row => {
  deleteTarget.value = row;
  deleteDialog.value?.open();
};

const doDelete = async () => {
  if (!deleteTarget.value) return;
  try {
    await paymentHandlesApi.delete(deleteTarget.value.id);
    useAlert(t('PAYMENT_HANDLES.SUCCESS_DELETED'));
    deleteDialog.value?.close();
    await loadHandles();
  } catch {
    useAlert(t('PAYMENT_HANDLES.ERROR_GENERIC'));
  }
};

const runEnable = async row => {
  try {
    await paymentHandlesApi.enable(row.id);
    await loadHandles();
  } catch {
    useAlert(t('PAYMENT_HANDLES.ERROR_GENERIC'));
  }
};

const runDisable = async row => {
  try {
    await paymentHandlesApi.disable(row.id);
    await loadHandles();
  } catch {
    useAlert(t('PAYMENT_HANDLES.ERROR_GENERIC'));
  }
};

const runResetFailures = async row => {
  try {
    await paymentHandlesApi.resetFailures(row.id);
    await loadHandles();
  } catch {
    useAlert(t('PAYMENT_HANDLES.ERROR_GENERIC'));
  }
};

watch(
  () => form.value.verification_email,
  val => {
    if (val && val.includes('@')) applyImapPreset(val);
  }
);

onMounted(() => {
  loadHandles();
  refreshTimer = setInterval(() => {
    nowTick.value = Date.now();
  }, 30_000);
});

onUnmounted(() => {
  if (refreshTimer) clearInterval(refreshTimer);
});
</script>

<template>
  <SettingsLayout :is-loading="isLoading">
    <template #header>
      <div class="flex flex-col gap-4 w-full">
        <div class="flex flex-wrap gap-3 justify-between items-start">
          <BaseSettingsHeader
            :title="t('PAYMENT_HANDLES.TITLE')"
            :description="t('PAYMENT_HANDLES.SUBTITLE')"
            feature-name="payment_handles"
            :back-button-label="$t('SIDEBAR.INTEGRATIONS')"
          />
          <Button
            :label="t('PAYMENT_HANDLES.ADD_BUTTON')"
            color="blue"
            class="shrink-0"
            @click="openCreate"
          />
        </div>
      </div>
    </template>
    <template #body>
      <div
        v-if="allDownForSelected"
        class="px-4 py-3 mb-4 text-sm rounded-lg border border-amber-500/40 bg-amber-500/10 text-amber-950 dark:text-amber-100"
      >
        {{ t('PAYMENT_HANDLES.ALL_HANDLES_DOWN_BANNER') }}
      </div>

      <div
        class="flex overflow-x-auto gap-1 p-1 mb-6 rounded-xl border border-n-weak bg-n-alpha-2"
      >
        <button
          v-for="plat in PLATFORMS"
          :key="plat.id"
          type="button"
          class="shrink-0 px-3 py-2 text-sm rounded-lg border transition-colors"
          :class="
            selectedPlatform === plat.id
              ? 'border-woot-500 bg-woot-50 dark:bg-woot-500/15 text-woot-700 dark:text-woot-200'
              : 'border-transparent text-n-slate-11 hover:bg-n-alpha-2'
          "
          @click="selectedPlatform = plat.id"
        >
          <span class="font-medium">{{ plat.label }}</span>
          <span class="ml-1.5 text-xs opacity-80">({{ tabBadge(plat) }})</span>
        </button>
      </div>

      <div
        v-if="!handlesForPlatform.length"
        class="py-16 text-center text-n-slate-11 border border-dashed border-n-weak rounded-xl"
      >
        {{ t('PAYMENT_HANDLES.NO_HANDLES_YET') }}
      </div>

      <ul v-else class="flex flex-col gap-2 p-0 m-0 list-none">
        <li
          v-for="row in handlesForPlatform"
          :key="row.id"
          class="flex flex-col gap-3 p-4 rounded-xl border border-n-weak bg-n-alpha-3 sm:flex-row sm:items-center sm:justify-between"
        >
          <div class="flex flex-col gap-1 min-w-0">
            <div class="flex flex-wrap gap-2 items-center">
              <span
                class="inline-flex justify-center items-center min-w-7 h-7 text-xs font-semibold rounded-full border border-n-weak text-n-slate-12"
              >
                {{ row.priority }}
              </span>
              <span class="font-semibold text-n-slate-12 truncate">
                {{ displayHandle(row) }}
              </span>
              <span
                class="inline-flex items-center px-2 py-0.5 text-xs font-medium rounded-full"
                :class="statusClass(row.status)"
              >
                {{ statusLabel(row.status) }}
              </span>
            </div>
            <p v-if="row.display_name" class="m-0 text-sm text-n-slate-11 truncate">
              {{ row.display_name }}
            </p>
            <p class="m-0 text-xs text-n-slate-11">
              {{ t('PAYMENT_HANDLES.FAILURES') }}: {{ row.failure_count || 0 }}
              <span v-if="row.last_used_at" class="ml-2">
                · {{ t('PAYMENT_HANDLES.LAST_USED') }}
                {{ dynamicTime(row.last_used_at) }}
              </span>
            </p>
            <p
              v-if="row.cooldown_until && new Date(row.cooldown_until) > new Date(nowTick)"
              class="m-0 text-xs text-n-slate-11"
            >
              {{ t('PAYMENT_HANDLES.COOLDOWN_UNTIL') }}
              {{ dynamicTime(row.cooldown_until) }}
            </p>
          </div>
          <div class="flex flex-wrap gap-2 shrink-0">
            <Button
              faded
              slate
              size="sm"
              :label="t('PAYMENT_HANDLES.EDIT_BUTTON')"
              @click="openEdit(row)"
            />
            <Button
              v-if="row.status === 'disabled'"
              faded
              slate
              size="sm"
              :label="t('PAYMENT_HANDLES.ENABLE_BUTTON')"
              @click="runEnable(row)"
            />
            <Button
              v-else
              faded
              slate
              size="sm"
              :label="t('PAYMENT_HANDLES.DISABLE_BUTTON')"
              @click="runDisable(row)"
            />
            <Button
              faded
              slate
              size="sm"
              :label="t('PAYMENT_HANDLES.RESET_FAILURES')"
              @click="runResetFailures(row)"
            />
            <Button
              faded
              ruby
              size="sm"
              :label="t('PAYMENT_HANDLES.DELETE_BUTTON')"
              @click="confirmDelete(row)"
            />
          </div>
        </li>
      </ul>

      <Dialog
        ref="formDialog"
        type="edit"
        width="2xl"
        overflow-y-auto
        :show-confirm-button="false"
        :cancel-button-label="t('PAYMENT_HANDLES.CANCEL')"
        :title="
          formMode === 'create'
            ? t('PAYMENT_HANDLES.ADD_MODAL_TITLE')
            : t('PAYMENT_HANDLES.EDIT_MODAL_TITLE')
        "
      >
        <div class="flex flex-col gap-4">
          <div class="grid gap-4 sm:grid-cols-2">
            <label class="flex flex-col gap-1 text-sm">
              <span class="text-n-slate-11">{{ t('PAYMENT_HANDLES.FORM_PLATFORM') }}</span>
              <select
                v-model="form.platform"
                :disabled="formMode === 'edit'"
                class="h-10 px-3 text-sm rounded-lg border bg-n-alpha-3 border-n-weak text-n-slate-12"
              >
                <option v-for="p in PLATFORMS" :key="p.id" :value="p.id">
                  {{ p.label }}
                </option>
              </select>
            </label>
            <label class="flex flex-col gap-1 text-sm">
              <span class="text-n-slate-11">{{ t('PAYMENT_HANDLES.FORM_PRIORITY') }}</span>
              <input
                v-model.number="form.priority"
                type="number"
                min="1"
                :max="platformMeta(form.platform).max"
                class="h-10 px-3 text-sm rounded-lg border bg-n-alpha-3 border-n-weak text-n-slate-12"
              />
            </label>
          </div>
          <label class="flex flex-col gap-1 text-sm">
            <span class="text-n-slate-11">{{ t('PAYMENT_HANDLES.FORM_HANDLE') }}</span>
            <input
              v-model="form.handle"
              type="text"
              class="h-10 px-3 text-sm rounded-lg border bg-n-alpha-3 border-n-weak text-n-slate-12"
            />
          </label>
          <label class="flex flex-col gap-1 text-sm">
            <span class="text-n-slate-11">{{ t('PAYMENT_HANDLES.FORM_DISPLAY_NAME') }}</span>
            <input
              v-model="form.display_name"
              type="text"
              class="h-10 px-3 text-sm rounded-lg border bg-n-alpha-3 border-n-weak text-n-slate-12"
            />
          </label>
          <label class="flex flex-col gap-1 text-sm">
            <span class="text-n-slate-11">{{ t('PAYMENT_HANDLES.FORM_NOTES') }}</span>
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
              class="transition-transform i-lucide-chevron-down"
              :class="{ 'rotate-180': emailSectionOpen }"
            />
            {{ t('PAYMENT_HANDLES.FORM_EMAIL_SECTION_TITLE') }}
          </button>
          <div v-show="emailSectionOpen" class="grid gap-4 p-4 rounded-xl border border-n-weak bg-n-alpha-2">
            <label class="flex flex-col gap-1 text-sm">
              <span class="text-n-slate-11">{{ t('PAYMENT_HANDLES.FORM_EMAIL') }}</span>
              <input
                v-model="form.verification_email"
                type="email"
                autocomplete="off"
                class="h-10 px-3 text-sm rounded-lg border bg-n-alpha-3 border-n-weak text-n-slate-12"
              />
            </label>
            <label class="flex flex-col gap-1 text-sm">
              <span class="text-n-slate-11">{{ t('PAYMENT_HANDLES.FORM_EMAIL_PASSWORD') }}</span>
              <input
                v-model="form.verification_email_password"
                type="password"
                autocomplete="new-password"
                :placeholder="
                  formMode === 'edit'
                    ? t('PAYMENT_HANDLES.FORM_PASSWORD_PLACEHOLDER')
                    : ''
                "
                class="h-10 px-3 text-sm rounded-lg border bg-n-alpha-3 border-n-weak text-n-slate-12"
              />
            </label>
            <div class="grid gap-4 sm:grid-cols-2">
              <label class="flex flex-col gap-1 text-sm">
                <span class="text-n-slate-11">{{ t('PAYMENT_HANDLES.FORM_EMAIL_HOST') }}</span>
                <input
                  v-model="form.verification_email_host"
                  type="text"
                  class="h-10 px-3 text-sm rounded-lg border bg-n-alpha-3 border-n-weak text-n-slate-12"
                />
              </label>
              <label class="flex flex-col gap-1 text-sm">
                <span class="text-n-slate-11">{{ t('PAYMENT_HANDLES.FORM_EMAIL_PORT') }}</span>
                <input
                  v-model.number="form.verification_email_port"
                  type="number"
                  class="h-10 px-3 text-sm rounded-lg border bg-n-alpha-3 border-n-weak text-n-slate-12"
                />
              </label>
            </div>
            <label class="inline-flex gap-2 items-center text-sm cursor-pointer select-none">
              <input v-model="form.verification_email_ssl" type="checkbox" class="rounded border-n-weak" />
              <span>{{ t('PAYMENT_HANDLES.FORM_EMAIL_SSL') }}</span>
            </label>
          </div>

          <div class="flex gap-2 justify-end pt-2">
            <Button
              faded
              slate
              :label="t('PAYMENT_HANDLES.CANCEL')"
              @click="formDialog?.close()"
            />
            <Button
              color="blue"
              :label="t('PAYMENT_HANDLES.SAVE')"
              :is-loading="formSubmitting"
              @click="submitForm"
            />
          </div>
        </div>
      </Dialog>

      <Dialog
        ref="deleteDialog"
        type="alert"
        :title="t('PAYMENT_HANDLES.DELETE_BUTTON')"
        :description="t('PAYMENT_HANDLES.DELETE_CONFIRM')"
        :confirm-button-label="t('PAYMENT_HANDLES.DELETE_BUTTON')"
        @confirm="doDelete"
      />
    </template>
  </SettingsLayout>
</template>
