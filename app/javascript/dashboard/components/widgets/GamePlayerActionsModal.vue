<template>
  <div class="modal-backdrop" @click.self="$emit('close')">
    <div class="modal">
      <header class="modal__head">
        <div class="modal__title-wrap">
          <div class="game-logo">{{ game.logo_emoji || '🎮' }}</div>
          <div>
            <h3 class="modal__title">{{ $t('GAMES.ACTIONS_MODAL.TITLE', { gameName: game.name }) }}</h3>
            <div class="modal__subtitle">{{ game.domain }}</div>
          </div>
        </div>
        <button class="modal__close" @click="$emit('close')">✕</button>
      </header>

      <div class="modal__body">
        <div v-if="resultBanner" class="result-banner" :class="resultBanner.ok ? 'result-banner--ok' : 'result-banner--error'">
          {{ resultBanner.message }}
        </div>

        <div class="field">
          <label class="field__label">{{ $t('GAMES.ACTIONS_MODAL.USERNAME_LABEL') }}</label>
          <input
            v-model="username"
            class="field__input"
            :placeholder="$t('GAMES.ACTIONS_MODAL.USERNAME_PLACEHOLDER')"
            @keyup.enter="onCheckBalance"
          />
        </div>

        <div class="balance-row">
          <button
            class="btn btn--ghost"
            :disabled="!username || isChecking"
            @click="onCheckBalance"
          >
            {{ isChecking ? '…' : $t('GAMES.ACTIONS_MODAL.CHECK_BALANCE_BTN') }}
          </button>
          <button type="button" class="btn btn--secondary" :disabled="diagnosing" @click="runDiagnose">
            {{ diagnosing ? '...' : 'Diagnose' }}
          </button>
          <span v-if="balance !== null" class="balance-result">
            {{ $t('GAMES.ACTIONS_MODAL.BALANCE_RESULT', { balance: balance }) }}
          </span>
        </div>

        <div v-if="result" class="result-banner" :class="resultOk ? 'result-banner--ok' : 'result-banner--error'">
          <pre class="diagnose-pre">{{ result }}</pre>
        </div>

        <div class="field">
          <label class="field__label">{{ $t('GAMES.ACTIONS_MODAL.AMOUNT_LABEL') }}</label>
          <input v-model.number="amount" class="field__input" type="number" min="0" step="0.01" placeholder="0.00" />
        </div>

        <div class="action-buttons">
          <button
            class="btn btn--primary"
            :disabled="!canSubmit || isSubmitting"
            @click="onLoad"
          >
            {{ isSubmitting && submitType === 'load' ? '…' : $t('GAMES.ACTIONS_MODAL.LOAD_BTN') }}
          </button>
          <button
            class="btn btn--danger-solid"
            :disabled="!canSubmit || isSubmitting"
            @click="onCashout"
          >
            {{ isSubmitting && submitType === 'cashout' ? '…' : $t('GAMES.ACTIONS_MODAL.CASHOUT_BTN') }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<script>
import GamesAPI from '../../api/games';

export default {
  name: 'GamePlayerActionsModal',
  props: {
    game: { type: Object, required: true },
    agentGame: { type: Object, required: true },
  },
  emits: ['close'],
  data() {
    return {
      username: '',
      amount: null,
      balance: null,
      isChecking: false,
      isSubmitting: false,
      submitType: null,
      resultBanner: null,
      diagnosing: false,
      result: '',
      resultOk: false,
    };
  },
  computed: {
    canSubmit() {
      return this.username && this.amount && this.amount > 0;
    },
  },
  methods: {
    async onCheckBalance() {
      if (!this.username) return;
      this.isChecking = true;
      this.balance = null;
      this.resultBanner = null;
      this.result = '';
      try {
        const response = await GamesAPI.checkPlayer(this.agentGame.id, this.username);
        if (response.data.ok) {
          this.balance = response.data.balance;
        } else {
          this.resultBanner = { ok: false, message: this.$t('GAMES.ACTIONS_MODAL.ERROR_PREFIX') + response.data.message };
        }
      } catch (err) {
        this.resultBanner = { ok: false, message: err.response?.data?.message || 'Check failed' };
      } finally {
        this.isChecking = false;
      }
    },
    async runDiagnose() {
      this.diagnosing = true;
      this.result = '';
      try {
        const { data } = await GamesAPI.diagnose(this.agentGame.id);
        const lines = [
          `Egress IP: ${data.patra_egress_ip}`,
          `Agent ID: ${data.agent_id}`,
          `IP whitelist confirmed: ${data.ip_whitelist_confirmed}`,
          `Balance call: ${data.balance_call?.ok ? '✅' : '❌'} ${data.balance_call?.message || data.balance_call?.error || ''}`,
          data.balance_call?.balance ? `Balance: $${data.balance_call.balance}` : ''
        ].filter(Boolean).join('\n');
        this.result = lines;
        this.resultOk = !!data.balance_call?.ok;
      } catch (e) {
        this.result = 'Diagnose failed: ' + (e.response?.data?.error || e.message);
        this.resultOk = false;
      } finally {
        this.diagnosing = false;
      }
    },
    async onLoad() {
      if (!this.canSubmit) return;
      this.isSubmitting = true;
      this.submitType = 'load';
      this.resultBanner = null;
      this.result = '';
      try {
        const response = await GamesAPI.loadPlayer(this.agentGame.id, {
          game_username: this.username,
          amount: this.amount,
        });
        if (response.data.ok) {
          this.resultBanner = { ok: true, message: this.$t('GAMES.ACTIONS_MODAL.LOAD_SUCCESS', { amount: this.amount, username: this.username }) };
          this.amount = null;
        } else {
          this.resultBanner = { ok: false, message: this.$t('GAMES.ACTIONS_MODAL.ERROR_PREFIX') + response.data.message };
        }
      } catch (err) {
        this.resultBanner = { ok: false, message: err.response?.data?.message || 'Load failed' };
      } finally {
        this.isSubmitting = false;
        this.submitType = null;
      }
    },
    async onCashout() {
      if (!this.canSubmit) return;
      const confirmed = window.confirm(`Cashout $${this.amount} from ${this.username}?\n\nThis will withdraw real money from the player's game balance.`);
      if (!confirmed) return;
      this.isSubmitting = true;
      this.submitType = 'cashout';
      this.resultBanner = null;
      this.result = '';
      try {
        const response = await GamesAPI.cashoutPlayer(this.agentGame.id, {
          game_username: this.username,
          amount: this.amount,
        });
        if (response.data.ok) {
          this.resultBanner = { ok: true, message: this.$t('GAMES.ACTIONS_MODAL.CASHOUT_SUCCESS', { amount: this.amount, username: this.username }) };
          this.amount = null;
        } else {
          this.resultBanner = { ok: false, message: this.$t('GAMES.ACTIONS_MODAL.ERROR_PREFIX') + response.data.message };
        }
      } catch (err) {
        this.resultBanner = { ok: false, message: err.response?.data?.message || 'Cashout failed' };
      } finally {
        this.isSubmitting = false;
        this.submitType = null;
      }
    },
  },
};
</script>

<style lang="scss" scoped>
.modal-backdrop {
  position: fixed; inset: 0;
  background: rgba(11, 8, 23, 0.7);
  backdrop-filter: blur(8px);
  display: flex; align-items: center; justify-content: center;
  z-index: 9999; padding: 20px;
}

.modal {
  background: #16102B !important;
  border: 1px solid #2D2356 !important;
  border-radius: 16px;
  width: 100%; max-width: 480px;
  max-height: 90vh;
  display: flex; flex-direction: column;
  overflow: hidden;
  color: #F4F1FF !important;
  font-family: 'Inter', sans-serif;

  &__head {
    padding: 18px 22px;
    border-bottom: 1px solid #2D2356;
    display: flex; justify-content: space-between; align-items: center;
  }

  &__title-wrap { display: flex; align-items: center; gap: 12px; }
  &__title {
    font-family: 'Space Grotesk', sans-serif;
    font-size: 17px; font-weight: 700; margin: 0;
    color: #F4F1FF !important;
  }
  &__subtitle {
    font-size: 11px;
    color: #6F6692 !important;
    font-family: 'JetBrains Mono', monospace;
    margin-top: 2px;
  }

  &__close {
    background: transparent !important;
    border: 1px solid #2D2356 !important;
    color: #A89FCC !important;
    width: 30px; height: 30px;
    border-radius: 7px;
    cursor: pointer;
    display: flex; align-items: center; justify-content: center;
    padding: 0;
    &:hover { color: #F4F1FF !important; border-color: #4A3A8A !important; }
  }

  &__body { padding: 22px; overflow-y: auto; }
}

.game-logo {
  width: 38px; height: 38px;
  border-radius: 9px;
  display: flex; align-items: center; justify-content: center;
  font-size: 18px;
  background: #1F1740 !important;
  border: 1px solid #2D2356 !important;
}

.field { margin-bottom: 14px;

  &__label {
    display: block; font-size: 12px;
    color: #A89FCC !important;
    margin-bottom: 6px; font-weight: 500;
  }

  &__input {
    width: 100%;
    background: #1F1740 !important;
    border: 1px solid #2D2356 !important;
    border-radius: 8px !important;
    padding: 9px 12px !important;
    color: #F4F1FF !important;
    font-size: 13px !important;
    font-family: 'JetBrains Mono', monospace !important;
    box-shadow: none !important; margin: 0 !important; height: auto !important;

    &::placeholder { color: #6F6692 !important; }
    &:focus {
      outline: 2px solid #D4AF37 !important;
      border-color: transparent !important;
      background: #1F1740 !important; box-shadow: none !important;
    }
  }
}

.balance-row {
  display: flex; align-items: center; gap: 10px;
  margin-bottom: 14px; flex-wrap: wrap;
}

.balance-result {
  font-size: 13px;
  color: #4ADE80;
  font-family: 'JetBrains Mono', monospace;
}

.action-buttons {
  display: flex; gap: 8px; margin-top: 16px;
  padding-top: 16px; border-top: 1px solid #2D2356;
}

.result-banner {
  padding: 10px 14px !important;
  border-radius: 8px;
  font-size: 13px;
  margin-bottom: 16px;

  &--ok {
    background: rgba(74, 222, 128, 0.12) !important;
    border: 1px solid rgba(74, 222, 128, 0.3) !important;
    color: #4ADE80 !important;
  }
  &--error {
    background: rgba(248, 113, 113, 0.12) !important;
    border: 1px solid rgba(248, 113, 113, 0.3) !important;
    color: #F87171 !important;
  }
}

.diagnose-pre {
  white-space: pre-wrap;
  margin: 0;
  font-family: 'JetBrains Mono', monospace;
  font-size: 12px;
}

.btn {
  font-family: 'Inter', sans-serif !important;
  font-size: 13px !important; font-weight: 600 !important;
  padding: 9px 16px !important;
  border-radius: 8px !important;
  border: 1px solid #2D2356 !important;
  background: #1F1740 !important;
  color: #F4F1FF !important;
  cursor: pointer; transition: all 0.15s;
  margin: 0 !important; height: auto !important;

  &:hover { border-color: #4A3A8A !important; background: #2D2356 !important; }
  &:disabled { opacity: 0.5 !important; cursor: not-allowed; }

  &--primary {
    background: #D4AF37 !important;
    color: #0B0817 !important;
    border-color: #D4AF37 !important;
    flex: 1;
    &:hover { background: #B8961F !important; border-color: #B8961F !important; }
  }

  &--ghost {
    background: transparent !important;
    color: #A89FCC !important;
    &:hover { color: #F4F1FF !important; border-color: #4A3A8A !important; }
  }

  &--danger-solid {
    background: rgba(248, 113, 113, 0.12) !important;
    color: #F87171 !important;
    border-color: rgba(248, 113, 113, 0.3) !important;
    flex: 1;
    &:hover {
      background: rgba(248, 113, 113, 0.18) !important;
      border-color: #F87171 !important;
    }
  }

  &--secondary {
    background: rgba(255, 255, 255, 0.06) !important;
    color: #A89FCC !important;
    border: 1px solid #2D2356 !important;
    &:hover:not(:disabled) {
      color: #F4F1FF !important;
      border-color: #4A3A8A !important;
    }
  }
}
</style>
