<template>
  <div class="notif-page">
    <div class="notif-header">
      <h1>{{ $t('NOTIFICATIONS.HEADER') }}</h1>
      <p class="muted">{{ $t('NOTIFICATIONS.DESCRIPTION') }}</p>
      <span :class="['status-pill', isConfigured ? 'connected' : 'not-connected']">
        {{ isConfigured ? $t('NOTIFICATIONS.STATUS.CONFIGURED') : $t('NOTIFICATIONS.STATUS.NOT_CONFIGURED') }}
      </span>
    </div>

    <div v-if="!isConfigured" class="setup-card">
      <h3>{{ $t('NOTIFICATIONS.SETUP_STEPS.TITLE') }}</h3>
      <ol>
        <li>{{ $t('NOTIFICATIONS.SETUP_STEPS.STEP_1') }}</li>
        <li>{{ $t('NOTIFICATIONS.SETUP_STEPS.STEP_2') }}</li>
        <li>{{ $t('NOTIFICATIONS.SETUP_STEPS.STEP_3') }}</li>
        <li>{{ $t('NOTIFICATIONS.SETUP_STEPS.STEP_4') }}</li>
      </ol>
    </div>

    <div class="form-card">
      <label>
        <span class="lbl">{{ $t('NOTIFICATIONS.FORM.BOT_TOKEN_LABEL') }}</span>
        <input
          v-model="botToken"
          type="text"
          :placeholder="$t('NOTIFICATIONS.FORM.BOT_TOKEN_PLACEHOLDER')"
        />
      </label>
      <label>
        <span class="lbl">{{ $t('NOTIFICATIONS.FORM.CHAT_ID_LABEL') }}</span>
        <input
          v-model="chatId"
          type="text"
          :placeholder="$t('NOTIFICATIONS.FORM.CHAT_ID_PLACEHOLDER')"
        />
      </label>

      <div class="filters">
        <span class="lbl">{{ $t('NOTIFICATIONS.FORM.EVENT_FILTERS_LABEL') }}</span>
        <label class="check"><input type="checkbox" v-model="filters.load_success" /> {{ $t('NOTIFICATIONS.FORM.EVENT_LOAD_SUCCESS') }}</label>
        <label class="check"><input type="checkbox" v-model="filters.load_failed" /> {{ $t('NOTIFICATIONS.FORM.EVENT_LOAD_FAILED') }}</label>
        <label class="check"><input type="checkbox" v-model="filters.cashout_request" /> {{ $t('NOTIFICATIONS.FORM.EVENT_CASHOUT_REQUEST') }}</label>
        <label class="check"><input type="checkbox" v-model="filters.cashout_failed" /> {{ $t('NOTIFICATIONS.FORM.EVENT_CASHOUT_FAILED') }}</label>
        <label class="check"><input type="checkbox" v-model="filters.human_escalation" /> {{ $t('NOTIFICATIONS.FORM.EVENT_HUMAN_ESCALATION') }}</label>
        <label class="check"><input type="checkbox" v-model="filters.api_error" /> {{ $t('NOTIFICATIONS.FORM.EVENT_API_ERROR') }}</label>
      </div>

      <div v-if="result" :class="['result', resultOk ? 'ok' : 'err']">{{ result }}</div>

      <div class="actions">
        <button class="btn btn--primary" :disabled="saving" @click="save">
          {{ saving ? '...' : $t('NOTIFICATIONS.FORM.SAVE_BTN') }}
        </button>
        <button class="btn btn--secondary" :disabled="testing || !channel?.id" @click="test">
          {{ testing ? '...' : $t('NOTIFICATIONS.FORM.TEST_BTN') }}
        </button>
        <button v-if="channel?.id" class="btn btn--danger" @click="remove">
          {{ $t('NOTIFICATIONS.FORM.DELETE_BTN') }}
        </button>
      </div>
    </div>
  </div>
</template>

<script>
import NotificationChannelsAPI from 'dashboard/api/notificationChannels';

export default {
  data() {
    return {
      channel: null,
      botToken: '',
      chatId: '',
      filters: {
        load_success: true,
        load_failed: true,
        cashout_request: true,
        cashout_failed: true,
        human_escalation: true,
        api_error: true
      },
      saving: false,
      testing: false,
      result: '',
      resultOk: false
    };
  },
  computed: {
    isConfigured() {
      return !!this.channel?.configured;
    }
  },
  async mounted() {
    await this.loadChannel();
  },
  methods: {
    async loadChannel() {
      try {
        const { data } = await NotificationChannelsAPI.get();
        const list = data?.data || [];
        const tg = list.find((c) => c.channel_type === 'telegram');
        if (tg) {
          this.channel = tg;
          // Don't pre-fill bot_token (it's masked from server); only chat_id which isn't sensitive
          this.chatId = tg.credentials?.chat_id || '';
          this.filters = { ...this.filters, ...(tg.event_filters || {}) };
        }
      } catch (e) {
        // No channel yet — that's fine
      }
    },
    async save() {
      this.saving = true;
      this.result = '';
      try {
        const payload = {
          channel_type: 'telegram',
          chat_id: this.chatId
        };
        if (this.botToken) payload.bot_token = this.botToken;
        payload.event_filters = this.filters;

        if (this.channel?.id) {
          const { data } = await NotificationChannelsAPI.update(this.channel.id, payload);
          this.channel = data.data;
        } else {
          const { data } = await NotificationChannelsAPI.create(payload);
          this.channel = data.data;
        }
        this.botToken = ''; // clear the field after save so it stays masked
        this.result = this.$t('NOTIFICATIONS.RESULT.SAVED');
        this.resultOk = true;
      } catch (e) {
        this.result = (this.$t('NOTIFICATIONS.RESULT.SAVE_ERROR')) + (e.response?.data?.error || e.message);
        this.resultOk = false;
      } finally {
        this.saving = false;
      }
    },
    async test() {
      if (!this.channel?.id) return;
      this.testing = true;
      this.result = '';
      try {
        const { data } = await NotificationChannelsAPI.testConnection(this.channel.id);
        if (data.ok) {
          this.result = this.$t('NOTIFICATIONS.RESULT.TEST_SENT');
          this.resultOk = true;
        } else {
          this.result = this.$t('NOTIFICATIONS.RESULT.TEST_FAILED') + (data.error || 'unknown');
          this.resultOk = false;
        }
      } catch (e) {
        this.result = this.$t('NOTIFICATIONS.RESULT.TEST_FAILED') + (e.response?.data?.error || e.message);
        this.resultOk = false;
      } finally {
        this.testing = false;
      }
    },
    async remove() {
      if (!this.channel?.id) return;
      if (!window.confirm(this.$t('NOTIFICATIONS.FORM.DELETE_CONFIRM'))) return;
      try {
        await NotificationChannelsAPI.delete(this.channel.id);
        this.channel = null;
        this.botToken = '';
        this.chatId = '';
        this.result = this.$t('NOTIFICATIONS.RESULT.DELETED');
        this.resultOk = true;
      } catch (e) {
        this.result = this.$t('NOTIFICATIONS.RESULT.DELETE_ERROR') + (e.response?.data?.error || e.message);
        this.resultOk = false;
      }
    }
  }
};
</script>

<style scoped lang="scss">
.notif-page {
  padding: 24px 32px;
  max-width: 720px;
  color: #F5F5F7 !important;
}
.notif-header h1 {
  font-size: 22px !important;
  font-weight: 600 !important;
  color: #F5F5F7 !important;
  margin-bottom: 4px !important;
}
.notif-header .muted {
  color: #A0A0AB !important;
  font-size: 14px !important;
  margin-bottom: 12px !important;
}
.status-pill {
  display: inline-block;
  padding: 4px 10px;
  border-radius: 999px;
  font-size: 12px;
  font-weight: 600;
}
.status-pill.connected {
  background: rgba(34, 197, 94, 0.15) !important;
  color: #4ADE80 !important;
}
.status-pill.not-connected {
  background: rgba(160, 160, 171, 0.15) !important;
  color: #A0A0AB !important;
}
.setup-card {
  margin-top: 16px;
  padding: 16px 20px;
  background: rgba(212, 175, 55, 0.06) !important;
  border: 1px solid rgba(212, 175, 55, 0.2) !important;
  border-radius: 12px;
}
.setup-card h3 {
  color: #D4AF37 !important;
  font-size: 14px !important;
  font-weight: 600 !important;
  margin: 0 0 8px !important;
}
.setup-card ol {
  margin: 0;
  padding-left: 20px;
  color: #C9C9D1 !important;
  font-size: 13px !important;
  line-height: 1.7 !important;
}
.form-card {
  margin-top: 24px;
  padding: 24px;
  background: rgba(255, 255, 255, 0.03) !important;
  border: 1px solid rgba(255, 255, 255, 0.08) !important;
  border-radius: 12px;
}
.form-card label {
  display: block;
  margin-bottom: 16px;
}
.lbl {
  display: block !important;
  font-size: 13px !important;
  font-weight: 500 !important;
  color: #C9C9D1 !important;
  margin-bottom: 6px !important;
}
.form-card input[type="text"] {
  width: 100% !important;
  padding: 10px 14px !important;
  background: rgba(0, 0, 0, 0.3) !important;
  border: 1px solid rgba(255, 255, 255, 0.1) !important;
  border-radius: 8px !important;
  color: #F5F5F7 !important;
  font-size: 14px !important;
  font-family: 'JetBrains Mono', monospace !important;
}
.form-card input[type="text"]:focus {
  border-color: #D4AF37 !important;
  outline: none !important;
}
.filters {
  margin: 20px 0 12px;
  display: flex;
  flex-wrap: wrap;
  gap: 10px 16px;
}
.filters .check {
  display: flex !important;
  align-items: center;
  gap: 6px;
  font-size: 13px !important;
  color: #C9C9D1 !important;
  margin: 0 !important;
  cursor: pointer;
}
.filters .check input {
  width: auto !important;
  margin: 0 !important;
}
.result {
  margin: 12px 0;
  padding: 10px 14px;
  border-radius: 8px;
  font-size: 13px;
}
.result.ok {
  background: rgba(34, 197, 94, 0.1) !important;
  color: #4ADE80 !important;
  border: 1px solid rgba(34, 197, 94, 0.2) !important;
}
.result.err {
  background: rgba(239, 68, 68, 0.1) !important;
  color: #F87171 !important;
  border: 1px solid rgba(239, 68, 68, 0.2) !important;
}
.actions {
  display: flex;
  gap: 10px;
  margin-top: 8px;
}
.btn {
  padding: 10px 16px !important;
  border-radius: 8px !important;
  font-size: 13px !important;
  font-weight: 600 !important;
  cursor: pointer !important;
  border: none !important;
  transition: all 0.15s ease !important;
}
.btn--primary {
  background: #D4AF37 !important;
  color: #0B0817 !important;
}
.btn--primary:hover:not(:disabled) {
  background: #E5C158 !important;
}
.btn--secondary {
  background: rgba(255, 255, 255, 0.06) !important;
  color: #F5F5F7 !important;
  border: 1px solid rgba(255, 255, 255, 0.1) !important;
}
.btn--secondary:hover:not(:disabled) {
  background: rgba(255, 255, 255, 0.1) !important;
}
.btn--danger {
  background: rgba(239, 68, 68, 0.1) !important;
  color: #F87171 !important;
  border: 1px solid rgba(239, 68, 68, 0.2) !important;
}
.btn--danger:hover {
  background: rgba(239, 68, 68, 0.2) !important;
}
.btn:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}
</style>
