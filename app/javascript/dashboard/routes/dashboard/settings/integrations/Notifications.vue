<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import NotificationChannelsAPI from 'dashboard/api/notificationChannels';
import NextButton from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();

const channel = ref(null);
const botToken = ref('');
const chatId = ref('');
const filters = ref({
  load_success: true,
  load_failed: true,
  cashout_request: true,
  cashout_failed: true,
  human_escalation: true,
  api_error: true,
});
const saving = ref(false);
const testing = ref(false);
const result = ref('');
const resultOk = ref(false);
const loading = ref(true);
const errorLoading = ref('');

const isConfigured = computed(() => Boolean(channel.value?.configured));

const loadChannel = async () => {
  loading.value = true;
  errorLoading.value = '';
  try {
    const { data } = await NotificationChannelsAPI.get();
    const list = data?.data || [];
    const tg = list.find(c => c.channel_type === 'telegram');
    if (tg) {
      channel.value = tg;
      chatId.value = tg.credentials?.chat_id || '';
      filters.value = { ...filters.value, ...(tg.event_filters || {}) };
    }
  } catch (e) {
    errorLoading.value =
      e.response?.data?.error || e.message || 'Failed to load notification settings';
  } finally {
    loading.value = false;
  }
};

const save = async () => {
  saving.value = true;
  result.value = '';
  try {
    const payload = {
      channel_type: 'telegram',
      chat_id: chatId.value,
      event_filters: filters.value,
    };
    if (botToken.value) payload.bot_token = botToken.value;

    if (channel.value?.id) {
      const { data } = await NotificationChannelsAPI.update(channel.value.id, payload);
      channel.value = data.data;
    } else {
      const { data } = await NotificationChannelsAPI.create(payload);
      channel.value = data.data;
    }
    botToken.value = '';
    result.value = t('NOTIFICATIONS.RESULT.SAVED');
    resultOk.value = true;
  } catch (e) {
    result.value =
      t('NOTIFICATIONS.RESULT.SAVE_ERROR') +
      (e.response?.data?.error || e.message);
    resultOk.value = false;
  } finally {
    saving.value = false;
  }
};

const test = async () => {
  if (!channel.value?.id) return;
  testing.value = true;
  result.value = '';
  try {
    const { data } = await NotificationChannelsAPI.testConnection(channel.value.id);
    if (data.ok) {
      result.value = t('NOTIFICATIONS.RESULT.TEST_SENT');
      resultOk.value = true;
    } else {
      result.value = t('NOTIFICATIONS.RESULT.TEST_FAILED') + (data.error || 'unknown');
      resultOk.value = false;
    }
  } catch (e) {
    result.value =
      t('NOTIFICATIONS.RESULT.TEST_FAILED') +
      (e.response?.data?.error || e.message);
    resultOk.value = false;
  } finally {
    testing.value = false;
  }
};

const remove = async () => {
  if (!channel.value?.id) return;
  if (!window.confirm(t('NOTIFICATIONS.FORM.DELETE_CONFIRM'))) return;
  try {
    await NotificationChannelsAPI.delete(channel.value.id);
    channel.value = null;
    botToken.value = '';
    chatId.value = '';
    result.value = t('NOTIFICATIONS.RESULT.DELETED');
    resultOk.value = true;
  } catch (e) {
    result.value =
      t('NOTIFICATIONS.RESULT.DELETE_ERROR') +
      (e.response?.data?.error || e.message);
    resultOk.value = false;
  }
};

onMounted(loadChannel);
</script>

<template>
  <div class="w-full max-w-2xl">
    <div class="mb-6">
      <h1 class="text-xl font-semibold text-n-slate-12">
        {{ $t('NOTIFICATIONS.HEADER') }}
      </h1>
      <p class="mt-1 text-sm text-n-slate-11">
        {{ $t('NOTIFICATIONS.DESCRIPTION') }}
      </p>
      <span
        class="mt-3 inline-block rounded-full px-3 py-1 text-xs font-semibold"
        :class="
          isConfigured
            ? 'bg-n-teal-3 text-n-teal-11'
            : 'bg-n-slate-3 text-n-slate-11'
        "
      >
        {{
          isConfigured
            ? $t('NOTIFICATIONS.STATUS.CONFIGURED')
            : $t('NOTIFICATIONS.STATUS.NOT_CONFIGURED')
        }}
      </span>
    </div>

    <div
      v-if="loading"
      class="rounded-xl border border-n-weak bg-n-alpha-1 px-6 py-8 text-center text-sm text-n-slate-11"
    >
      Loading your notification settings…
    </div>

    <div
      v-else-if="errorLoading"
      class="rounded-xl border border-n-ruby-6 bg-n-ruby-2 px-6 py-8 text-center text-sm text-n-ruby-11"
    >
      ⚠️ {{ errorLoading }}
      <div class="mt-3">
        <NextButton
          :label="$t('NOTIFICATIONS.FORM.RETRY')"
          slate
          sm
          @click="loadChannel"
        />
      </div>
    </div>

    <template v-else>
      <div
        v-if="!isConfigured"
        class="mb-6 rounded-xl border border-n-amber-6 bg-n-amber-2 px-5 py-4"
      >
        <h3 class="text-sm font-semibold text-n-amber-11">
          {{ $t('NOTIFICATIONS.SETUP_STEPS.TITLE') }}
        </h3>
        <ol class="mt-2 list-decimal space-y-1 pl-5 text-sm text-n-slate-11">
          <li>{{ $t('NOTIFICATIONS.SETUP_STEPS.STEP_1') }}</li>
          <li>{{ $t('NOTIFICATIONS.SETUP_STEPS.STEP_2') }}</li>
          <li>{{ $t('NOTIFICATIONS.SETUP_STEPS.STEP_3') }}</li>
          <li>{{ $t('NOTIFICATIONS.SETUP_STEPS.STEP_4') }}</li>
        </ol>
      </div>

      <div class="rounded-xl border border-n-weak bg-n-solid-1 p-6">
        <label class="mb-4 block">
          <span class="mb-1 block text-sm font-medium text-n-slate-12">
            {{ $t('NOTIFICATIONS.FORM.BOT_TOKEN_LABEL') }}
          </span>
          <input
            v-model="botToken"
            type="text"
            class="w-full rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-12 placeholder:text-n-slate-10 focus:border-n-brand focus:outline-none"
            :placeholder="$t('NOTIFICATIONS.FORM.BOT_TOKEN_PLACEHOLDER')"
          />
        </label>

        <label class="mb-4 block">
          <span class="mb-1 block text-sm font-medium text-n-slate-12">
            {{ $t('NOTIFICATIONS.FORM.CHAT_ID_LABEL') }}
          </span>
          <input
            v-model="chatId"
            type="text"
            class="w-full rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-12 placeholder:text-n-slate-10 focus:border-n-brand focus:outline-none"
            :placeholder="$t('NOTIFICATIONS.FORM.CHAT_ID_PLACEHOLDER')"
          />
        </label>

        <div class="mb-4">
          <span class="mb-2 block text-sm font-medium text-n-slate-12">
            {{ $t('NOTIFICATIONS.FORM.EVENT_FILTERS_LABEL') }}
          </span>
          <div class="flex flex-wrap gap-x-4 gap-y-2">
            <label class="flex items-center gap-2 text-sm text-n-slate-11">
              <input v-model="filters.load_success" type="checkbox" />
              {{ $t('NOTIFICATIONS.FORM.EVENT_LOAD_SUCCESS') }}
            </label>
            <label class="flex items-center gap-2 text-sm text-n-slate-11">
              <input v-model="filters.load_failed" type="checkbox" />
              {{ $t('NOTIFICATIONS.FORM.EVENT_LOAD_FAILED') }}
            </label>
            <label class="flex items-center gap-2 text-sm text-n-slate-11">
              <input v-model="filters.cashout_request" type="checkbox" />
              {{ $t('NOTIFICATIONS.FORM.EVENT_CASHOUT_REQUEST') }}
            </label>
            <label class="flex items-center gap-2 text-sm text-n-slate-11">
              <input v-model="filters.cashout_failed" type="checkbox" />
              {{ $t('NOTIFICATIONS.FORM.EVENT_CASHOUT_FAILED') }}
            </label>
            <label class="flex items-center gap-2 text-sm text-n-slate-11">
              <input v-model="filters.human_escalation" type="checkbox" />
              {{ $t('NOTIFICATIONS.FORM.EVENT_HUMAN_ESCALATION') }}
            </label>
            <label class="flex items-center gap-2 text-sm text-n-slate-11">
              <input v-model="filters.api_error" type="checkbox" />
              {{ $t('NOTIFICATIONS.FORM.EVENT_API_ERROR') }}
            </label>
          </div>
        </div>

        <div
          v-if="result"
          class="mb-4 rounded-lg px-3 py-2 text-sm"
          :class="
            resultOk
              ? 'border border-n-teal-6 bg-n-teal-2 text-n-teal-11'
              : 'border border-n-ruby-6 bg-n-ruby-2 text-n-ruby-11'
          "
        >
          {{ result }}
        </div>

        <div class="flex flex-wrap gap-2">
          <NextButton
            :label="saving ? '…' : $t('NOTIFICATIONS.FORM.SAVE_BTN')"
            :disabled="saving"
            @click="save"
          />
          <NextButton
            :label="testing ? '…' : $t('NOTIFICATIONS.FORM.TEST_BTN')"
            slate
            :disabled="testing || !channel?.id"
            @click="test"
          />
          <NextButton
            v-if="channel?.id"
            :label="$t('NOTIFICATIONS.FORM.DELETE_BTN')"
            ruby
            @click="remove"
          />
        </div>
      </div>
    </template>
  </div>
</template>
