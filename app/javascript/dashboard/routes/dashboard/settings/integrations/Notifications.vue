<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import NotificationChannelsAPI from 'dashboard/api/notificationChannels';

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
const spotlight = ref(null);

const isConfigured = computed(() => Boolean(channel.value?.configured));

const saveLabel = computed(() =>
  saving.value
    ? t('NOTIFICATIONS.FORM.SAVING')
    : t('NOTIFICATIONS.FORM.SAVE_BTN')
);

const testLabel = computed(() =>
  testing.value
    ? t('NOTIFICATIONS.FORM.TESTING')
    : t('NOTIFICATIONS.FORM.TEST_BTN')
);

const eventFilters = computed(() => [
  {
    key: 'load_success',
    label: t('NOTIFICATIONS.FORM.EVENT_LOAD_SUCCESS'),
    subtitle: t('NOTIFICATIONS.FORM.EVENT_LOAD_SUCCESS_DESC'),
  },
  {
    key: 'load_failed',
    label: t('NOTIFICATIONS.FORM.EVENT_LOAD_FAILED'),
    subtitle: t('NOTIFICATIONS.FORM.EVENT_LOAD_FAILED_DESC'),
  },
  {
    key: 'cashout_request',
    label: t('NOTIFICATIONS.FORM.EVENT_CASHOUT_REQUEST'),
    subtitle: t('NOTIFICATIONS.FORM.EVENT_CASHOUT_REQUEST_DESC'),
  },
  {
    key: 'cashout_failed',
    label: t('NOTIFICATIONS.FORM.EVENT_CASHOUT_FAILED'),
    subtitle: t('NOTIFICATIONS.FORM.EVENT_CASHOUT_FAILED_DESC'),
  },
  {
    key: 'human_escalation',
    label: t('NOTIFICATIONS.FORM.EVENT_HUMAN_ESCALATION'),
    subtitle: t('NOTIFICATIONS.FORM.EVENT_HUMAN_ESCALATION_DESC'),
  },
  {
    key: 'api_error',
    label: t('NOTIFICATIONS.FORM.EVENT_API_ERROR'),
    subtitle: t('NOTIFICATIONS.FORM.EVENT_API_ERROR_DESC'),
  },
]);

const toggleFilter = key => {
  filters.value[key] = !filters.value[key];
};

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
      e.response?.data?.error ||
      e.message ||
      'Failed to load notification settings';
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
      const { data } = await NotificationChannelsAPI.update(
        channel.value.id,
        payload
      );
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
    const { data } = await NotificationChannelsAPI.testConnection(
      channel.value.id
    );
    if (data.ok) {
      result.value = t('NOTIFICATIONS.RESULT.TEST_SENT');
      resultOk.value = true;
    } else {
      result.value =
        t('NOTIFICATIONS.RESULT.TEST_FAILED') + (data.error || 'unknown');
      resultOk.value = false;
    }
  } catch (e) {
    result.value =
      t('NOTIFICATIONS.RESULT.TEST_FAILED') +
      (e.response?.data?.error || e.message);
    resultOk.value = false;
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

const onSpotlightMove = e => {
  const el = spotlight.value;
  if (!el) return;
  el.style.left = `${e.clientX}px`;
  el.style.top = `${e.clientY}px`;
  el.style.opacity = '1';
};

const onSpotlightLeave = () => {
  const el = spotlight.value;
  if (el) el.style.opacity = '0';
};

const onCardGlow = e => {
  const card = e.target.closest('.card');
  if (!card) return;
  const rect = card.getBoundingClientRect();
  card.style.setProperty('--gx', `${e.clientX - rect.left}px`);
  card.style.setProperty('--gy', `${e.clientY - rect.top}px`);
};

onMounted(loadChannel);
</script>

<template>
  <div
    class="pat-notif-wrap"
    @mousemove="onSpotlightMove"
    @mouseleave="onSpotlightLeave"
  >
    <div id="spotlight" ref="spotlight" />
    <div class="mesh" />

    <div class="pat-notif-main" @mousemove="onCardGlow">
      <div class="sec-head">
        <h1 class="display">{{ $t('NOTIFICATIONS.HEADER') }}</h1>
        <div class="sub">{{ $t('NOTIFICATIONS.DESCRIPTION') }}</div>
        <span
          class="status-badge"
          :class="isConfigured ? 'status-on' : 'status-off'"
        >
          {{
            isConfigured
              ? $t('NOTIFICATIONS.STATUS.CONFIGURED')
              : $t('NOTIFICATIONS.STATUS.NOT_CONFIGURED')
          }}
        </span>
      </div>

      <div v-if="loading" class="card">
        <p class="loading-note">{{ $t('NOTIFICATIONS.LOADING') }}</p>
      </div>

      <div v-if="!loading && errorLoading" class="card card-error">
        <p class="error-text">{{ errorLoading }}</p>
        <button type="button" class="btn sm retry-btn" @click="loadChannel">
          {{ $t('NOTIFICATIONS.FORM.RETRY') }}
        </button>
      </div>

      <template v-if="!loading">
        <div v-if="!isConfigured" class="card card-setup">
          <div class="card-t">
            <span class="dot" />
            {{ $t('NOTIFICATIONS.SETUP_STEPS.TITLE') }}
          </div>
          <ol class="setup-list">
            <li>{{ $t('NOTIFICATIONS.SETUP_STEPS.STEP_1') }}</li>
            <li>{{ $t('NOTIFICATIONS.SETUP_STEPS.STEP_2') }}</li>
            <li>{{ $t('NOTIFICATIONS.SETUP_STEPS.STEP_3') }}</li>
            <li>{{ $t('NOTIFICATIONS.SETUP_STEPS.STEP_4') }}</li>
          </ol>
        </div>

        <div class="card">
          <div class="fld">
            <label>{{ $t('NOTIFICATIONS.FORM.BOT_TOKEN_LABEL') }}</label>
            <input
              v-model="botToken"
              type="text"
              :placeholder="$t('NOTIFICATIONS.FORM.BOT_TOKEN_PLACEHOLDER')"
            />
          </div>

          <div class="fld">
            <label>{{ $t('NOTIFICATIONS.FORM.CHAT_ID_LABEL') }}</label>
            <input
              v-model="chatId"
              type="text"
              :placeholder="$t('NOTIFICATIONS.FORM.CHAT_ID_PLACEHOLDER')"
            />
          </div>

          <div class="filters-section">
            <div class="filters-label">
              {{ $t('NOTIFICATIONS.FORM.EVENT_FILTERS_LABEL') }}
            </div>

            <div v-for="item in eventFilters" :key="item.key" class="tog-row">
              <div class="tr-l">
                <div class="tt">{{ item.label }}</div>
                <div class="ts">{{ item.subtitle }}</div>
              </div>
              <button
                type="button"
                class="sw"
                :class="{ off: !filters[item.key] }"
                :aria-pressed="filters[item.key]"
                @click="toggleFilter(item.key)"
              >
                <i />
              </button>
            </div>
          </div>

          <div
            v-if="result"
            class="result-banner"
            :class="resultOk ? 'result-ok' : 'result-err'"
          >
            {{ result }}
          </div>

          <div class="action-row">
            <button
              type="button"
              class="btn primary"
              :disabled="saving"
              @click="save"
            >
              {{ saveLabel }}
            </button>
            <button
              type="button"
              class="btn"
              :disabled="testing || !channel?.id"
              @click="test"
            >
              {{ testLabel }}
            </button>
            <button
              v-if="channel?.id"
              type="button"
              class="btn btn-danger"
              @click="remove"
            >
              {{ $t('NOTIFICATIONS.FORM.DELETE_BTN') }}
            </button>
          </div>
        </div>
      </template>
    </div>
  </div>
</template>

<style scoped>
.pat-notif-wrap {
  --canvas: #050409;
  --surface: #0c0b12;
  --surface-2: #131119;
  --surface-3: #1b1925;
  --surface-4: #252233;
  --border: #171520;
  --border-hi: #2e2940;
  --patra: #6e56cf;
  --patra-2: #8b5cf6;
  --patra-3: #a78bfa;
  --patra-deep: #5b45b0;
  --patra-glow: rgba(110, 86, 207, 0.55);
  --text: #ededf2;
  --text-2: #a8a6b6;
  --text-3: #75727f;
  --text-4: #54515e;
  --green: #3fb950;
  --red: #f85149;
  --amber: #e3a008;
  --mesh-1: rgba(110, 86, 207, 0.16);
  --mesh-2: rgba(139, 92, 246, 0.1);
  --mesh-3: rgba(236, 72, 153, 0.05);

  position: relative;
  min-height: 100%;
  color: var(--text);
  font-family: 'Inter', sans-serif;
  background: var(--canvas);
  overflow: hidden;
}

.display {
  font-family: 'Space Grotesk', sans-serif;
}

#spotlight {
  position: fixed;
  width: 460px;
  height: 460px;
  border-radius: 50%;
  background: radial-gradient(
    circle,
    rgba(110, 86, 207, 0.16),
    rgba(110, 86, 207, 0.04) 42%,
    transparent 66%
  );
  pointer-events: none;
  z-index: 0;
  transform: translate(-50%, -50%);
  opacity: 0;
  transition: opacity 0.5s;
  mix-blend-mode: screen;
  filter: blur(12px);
}

.mesh {
  position: fixed;
  inset: 0;
  pointer-events: none;
  z-index: 0;
  overflow: hidden;
}

.mesh::before,
.mesh::after {
  content: '';
  position: absolute;
  border-radius: 50%;
  filter: blur(100px);
}

.mesh::before {
  top: -15%;
  right: -5%;
  width: 700px;
  height: 560px;
  background:
    radial-gradient(circle at 40% 40%, var(--mesh-1), transparent 60%),
    radial-gradient(circle at 70% 70%, var(--mesh-2), transparent 60%);
  animation: meshA 22s ease-in-out infinite alternate;
}

.mesh::after {
  bottom: -20%;
  left: 10%;
  width: 560px;
  height: 500px;
  background: radial-gradient(
    circle at 50% 50%,
    var(--mesh-3),
    transparent 65%
  );
  animation: meshB 28s ease-in-out infinite alternate;
}

@keyframes meshA {
  0% {
    transform: translate(0, 0) scale(1);
  }
  100% {
    transform: translate(-50px, 40px) scale(1.12) rotate(8deg);
  }
}

@keyframes meshB {
  0% {
    transform: translate(0, 0) scale(1);
  }
  100% {
    transform: translate(40px, -30px) scale(1.1);
  }
}

.pat-notif-main {
  position: relative;
  z-index: 1;
  padding: 26px 32px 60px;
  max-width: 760px;
}

.sec-head {
  margin-bottom: 22px;
}

.sec-head h1 {
  font-weight: 600;
  font-size: 23px;
  margin: 0;
}

.sec-head .sub {
  font-size: 13px;
  color: var(--text-3);
  margin-top: 4px;
  line-height: 1.55;
}

.status-badge {
  display: inline-block;
  margin-top: 12px;
  border-radius: 20px;
  padding: 4px 12px;
  font-size: 11px;
  font-weight: 600;
  font-family: 'JetBrains Mono', monospace;
}

.status-on {
  color: var(--green);
  background: rgba(63, 185, 80, 0.16);
}

.status-off {
  color: var(--text-3);
  background: var(--surface-3);
}

.card {
  position: relative;
  isolation: isolate;
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 16px;
  padding: 22px;
  margin-bottom: 16px;
  transition:
    transform 0.35s cubic-bezier(0.34, 1.56, 0.64, 1),
    box-shadow 0.35s,
    border-color 0.25s;
}

.card::before {
  content: '';
  position: absolute;
  inset: 0;
  border-radius: inherit;
  pointer-events: none;
  opacity: 0;
  transition: opacity 0.3s;
  background: radial-gradient(
    260px circle at var(--gx, 50%) var(--gy, 50%),
    rgba(110, 86, 207, 0.15),
    transparent 70%
  );
  z-index: -1;
}

.card:hover::before {
  opacity: 1;
}

.card:hover {
  transform: translateY(-4px) scale(1.008);
  box-shadow:
    0 18px 40px -14px rgba(0, 0, 0, 0.55),
    0 0 26px rgba(110, 86, 207, 0.18);
  border-color: var(--patra);
}

.card-error {
  border-color: rgba(248, 81, 73, 0.35);
}

.card-setup {
  border-color: rgba(227, 160, 8, 0.35);
}

.loading-note {
  margin: 0;
  text-align: center;
  color: var(--text-3);
  font-size: 13px;
  padding: 24px 0;
}

.error-text {
  margin: 0 0 12px;
  font-size: 13px;
  color: var(--red);
}

.retry-btn {
  margin-top: 4px;
}

.card-t {
  font-family: 'Space Grotesk', sans-serif;
  font-weight: 600;
  font-size: 15px;
  display: flex;
  align-items: center;
  gap: 8px;
  margin-bottom: 14px;
}

.card-t .dot {
  width: 7px;
  height: 7px;
  border-radius: 50%;
  background: var(--patra-2);
  box-shadow: 0 0 8px var(--patra-glow);
}

.setup-list {
  margin: 0;
  padding-left: 20px;
  font-size: 13px;
  color: var(--text-2);
  line-height: 1.65;
}

.setup-list li + li {
  margin-top: 6px;
}

.fld {
  margin-bottom: 16px;
}

.fld label {
  display: block;
  font-size: 12.5px;
  color: var(--text-2);
  margin-bottom: 6px;
  font-weight: 500;
}

.fld input {
  width: 100%;
  background: var(--canvas);
  border: 1px solid var(--border);
  border-radius: 10px;
  padding: 10px 13px;
  color: var(--text);
  font-size: 13px;
  outline: none;
  transition: all 0.25s;
  font-family: 'Inter', sans-serif;
}

.fld input:focus {
  border-color: var(--patra);
  box-shadow: 0 0 0 3px rgba(110, 86, 207, 0.11);
}

.filters-section {
  margin-bottom: 16px;
}

.filters-label {
  font-size: 12.5px;
  color: var(--text-2);
  margin-bottom: 4px;
  font-weight: 500;
}

.tog-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 12px 0;
  border-bottom: 1px solid var(--border);
}

.tog-row:last-child {
  border-bottom: none;
}

.tog-row .tr-l .tt {
  font-size: 13.5px;
  font-weight: 500;
}

.tog-row .tr-l .ts {
  font-size: 11.5px;
  color: var(--text-3);
  margin-top: 2px;
}

.sw {
  width: 38px;
  height: 22px;
  border-radius: 12px;
  background: linear-gradient(135deg, var(--patra), var(--patra-2));
  position: relative;
  cursor: pointer;
  flex-shrink: 0;
  box-shadow: 0 0 12px var(--patra-glow);
  transition: all 0.3s;
  border: none;
  padding: 0;
}

.sw i {
  position: absolute;
  top: 2px;
  right: 2px;
  width: 18px;
  height: 18px;
  border-radius: 50%;
  background: #fff;
  transition: all 0.3s;
  display: block;
}

.sw.off {
  background: var(--surface-4);
  box-shadow: none;
}

.sw.off i {
  right: auto;
  left: 2px;
}

.result-banner {
  margin-bottom: 16px;
  border-radius: 10px;
  padding: 10px 13px;
  font-size: 13px;
}

.result-ok {
  border: 1px solid rgba(63, 185, 80, 0.35);
  background: rgba(63, 185, 80, 0.12);
  color: var(--green);
}

.result-err {
  border: 1px solid rgba(248, 81, 73, 0.35);
  background: rgba(248, 81, 73, 0.12);
  color: var(--red);
}

.action-row {
  display: flex;
  flex-wrap: wrap;
  gap: 10px;
}

.btn {
  font-size: 13px;
  font-weight: 600;
  padding: 10px 18px;
  border-radius: 10px;
  border: 1px solid var(--border-hi);
  background: var(--surface-2);
  color: var(--text);
  cursor: pointer;
  transition: all 0.22s cubic-bezier(0.34, 1.56, 0.64, 1);
}

.btn:hover:not(:disabled) {
  transform: translateY(-2px);
  box-shadow: 0 6px 16px rgba(0, 0, 0, 0.3);
  border-color: var(--patra);
}

.btn:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

.btn.primary {
  background: linear-gradient(135deg, var(--patra), var(--patra-deep));
  border-color: transparent;
  color: #fff;
  box-shadow: 0 4px 14px var(--patra-glow);
}

.btn.primary:hover:not(:disabled) {
  filter: brightness(1.12);
}

.btn.sm {
  padding: 7px 13px;
  font-size: 12px;
}

.btn-danger {
  border-color: rgba(248, 81, 73, 0.35);
  color: var(--red);
}

.btn-danger:hover:not(:disabled) {
  background: var(--red);
  color: #fff;
  border-color: transparent;
}
</style>
