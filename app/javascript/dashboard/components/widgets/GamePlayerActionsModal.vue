<script>
import GamesAPI from '../../api/games';

const CLUSTER_2_SLUGS = ['mafia', 'game_room', 'cash_machine', 'mr_all_in_one'];
const FASTAPI_NO_UNDERSCORE_SLUGS = ['vblink', 'ultra_panda'];

function passwordFromUsername(username, gameSlug) {
  const name = username.toString().trim();
  if (!name) return '';
  if (
    gameSlug &&
    (CLUSTER_2_SLUGS.includes(gameSlug) ||
      FASTAPI_NO_UNDERSCORE_SLUGS.includes(gameSlug))
  ) {
    return name.replace(/[a-z]{2,3}$/i, '');
  }
  return name.split('_')[0] || name;
}

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
      newPassword: '',
      balance: null,
      isChecking: false,
      isCreating: false,
      isResetting: false,
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
        const response = await GamesAPI.checkPlayer(
          this.agentGame.id,
          this.username
        );
        if (response.data.ok) {
          this.balance = response.data.balance;
        } else {
          this.resultBanner = {
            ok: false,
            message:
              this.$t('GAMES.ACTIONS_MODAL.ERROR_PREFIX') +
              response.data.message,
          };
        }
      } catch (err) {
        this.resultBanner = {
          ok: false,
          message: err.response?.data?.message || 'Check failed',
        };
      } finally {
        this.isChecking = false;
      }
    },
    async onCreatePlayer() {
      if (!this.username) return;
      this.isCreating = true;
      this.resultBanner = null;
      this.result = '';
      try {
        const password = passwordFromUsername(this.username, this.game.slug);
        const response = await GamesAPI.addPlayer(this.agentGame.id, {
          game_username: this.username.trim(),
          password: password || undefined,
        });
        if (response.data.ok) {
          const pwd = response.data.password || password;
          this.resultBanner = {
            ok: true,
            message: this.$t('GAMES.ACTIONS_MODAL.CREATE_SUCCESS', {
              username: this.username,
              password: pwd,
            }),
          };
        } else {
          this.resultBanner = {
            ok: false,
            message:
              this.$t('GAMES.ACTIONS_MODAL.ERROR_PREFIX') +
              response.data.message,
          };
        }
      } catch (err) {
        this.resultBanner = {
          ok: false,
          message: err.response?.data?.message || 'Create failed',
        };
      } finally {
        this.isCreating = false;
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
          data.balance_call?.balance
            ? `Balance: $${data.balance_call.balance}`
            : '',
        ]
          .filter(Boolean)
          .join('\n');
        this.result = lines;
        this.resultOk = !!data.balance_call?.ok;
      } catch (e) {
        this.result =
          'Diagnose failed: ' + (e.response?.data?.error || e.message);
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
          this.resultBanner = {
            ok: true,
            message: this.$t('GAMES.ACTIONS_MODAL.LOAD_SUCCESS', {
              amount: this.amount,
              username: this.username,
            }),
          };
          this.amount = null;
        } else {
          this.resultBanner = {
            ok: false,
            message:
              this.$t('GAMES.ACTIONS_MODAL.ERROR_PREFIX') +
              response.data.message,
          };
        }
      } catch (err) {
        this.resultBanner = {
          ok: false,
          message: err.response?.data?.message || 'Load failed',
        };
      } finally {
        this.isSubmitting = false;
        this.submitType = null;
      }
    },
    async onCashout() {
      if (!this.canSubmit) return;
      const confirmed = window.confirm(
        `Cashout $${this.amount} from ${this.username}?\n\nThis will withdraw real money from the player's game balance.`
      );
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
          this.resultBanner = {
            ok: true,
            message: this.$t('GAMES.ACTIONS_MODAL.CASHOUT_SUCCESS', {
              amount: this.amount,
              username: this.username,
            }),
          };
          this.amount = null;
        } else {
          this.resultBanner = {
            ok: false,
            message:
              this.$t('GAMES.ACTIONS_MODAL.ERROR_PREFIX') +
              response.data.message,
          };
        }
      } catch (err) {
        this.resultBanner = {
          ok: false,
          message: err.response?.data?.message || 'Cashout failed',
        };
      } finally {
        this.isSubmitting = false;
        this.submitType = null;
      }
    },
    async onResetPassword() {
      if (!this.username) return;
      this.isResetting = true;
      this.resultBanner = null;
      this.result = '';
      try {
        const payload = { game_username: this.username.trim() };
        if (this.newPassword.trim())
          payload.new_password = this.newPassword.trim();
        const response = await GamesAPI.resetPlayerPassword(
          this.agentGame.id,
          payload
        );
        if (response.data.ok) {
          this.resultBanner = {
            ok: true,
            message: this.$t('GAMES.ACTIONS_MODAL.RESET_SUCCESS', {
              password: response.data.new_password,
            }),
          };
          this.newPassword = '';
        } else {
          this.resultBanner = {
            ok: false,
            message:
              this.$t('GAMES.ACTIONS_MODAL.ERROR_PREFIX') +
              response.data.message,
          };
        }
      } catch (err) {
        this.resultBanner = {
          ok: false,
          message: err.response?.data?.message || 'Reset failed',
        };
      } finally {
        this.isResetting = false;
      }
    },
  },
};
</script>

<template>
  <div class="overlay show" @click.self="$emit('close')">
    <div class="modal">
      <div class="modal-h">
        <div class="mic">{{ game.logo_emoji || '🎮' }}</div>
        <div class="mt">
          <div class="mn">
            {{ $t('GAMES.ACTIONS_MODAL.TITLE', { gameName: game.name }) }}
          </div>
          <div class="md">{{ game.domain }}</div>
        </div>
        <button type="button" class="modal-x" @click="$emit('close')">
          {{ $t('GAMES.ACTIONS.CLOSE_ICON') }}
        </button>
      </div>

      <div class="modal-body">
        <div
          v-if="resultBanner"
          class="result-banner"
          :class="
            resultBanner.ok ? 'result-banner--ok' : 'result-banner--error'
          "
        >
          {{ resultBanner.message }}
        </div>

        <div class="mfield">
          <label>{{ $t('GAMES.ACTIONS_MODAL.USERNAME_LABEL') }}</label>
          <input
            v-model="username"
            :placeholder="$t('GAMES.ACTIONS_MODAL.USERNAME_PLACEHOLDER')"
            @keyup.enter="onCheckBalance"
          />
        </div>

        <div class="mp-ops mp-ops--top">
          <button
            type="button"
            class="mbtn ops-check"
            :disabled="!username || isChecking"
            @click="onCheckBalance"
          >
            {{
              isChecking
                ? $t('GAMES.ACTIONS_MODAL.BUSY_ELLIPSIS')
                : $t('GAMES.ACTIONS_MODAL.CHECK_BALANCE_BTN')
            }}
          </button>
          <button
            type="button"
            class="mbtn"
            :disabled="!username || isCreating"
            @click="onCreatePlayer"
          >
            {{
              isCreating
                ? $t('GAMES.ACTIONS_MODAL.BUSY_ELLIPSIS')
                : $t('GAMES.ACTIONS_MODAL.CREATE_PLAYER_BTN')
            }}
          </button>
          <button
            type="button"
            class="mbtn ops-diag full"
            :disabled="diagnosing"
            @click="runDiagnose"
          >
            {{
              diagnosing
                ? $t('GAMES.ACTIONS_MODAL.DIAGNOSING_ELLIPSIS')
                : $t('GAMES.ACTIONS_MODAL.DIAGNOSE_BTN')
            }}
          </button>
        </div>

        <span v-if="balance !== null" class="balance-result">
          {{ $t('GAMES.ACTIONS_MODAL.BALANCE_RESULT', { balance: balance }) }}
        </span>

        <div
          v-if="result"
          class="result-banner diagnose-block"
          :class="resultOk ? 'result-banner--ok' : 'result-banner--error'"
        >
          <pre class="diagnose-pre">{{ result }}</pre>
        </div>

        <div class="mfield">
          <label>{{ $t('GAMES.ACTIONS_MODAL.AMOUNT_LABEL') }}</label>
          <input
            v-model.number="amount"
            type="number"
            min="0"
            step="0.01"
            :placeholder="$t('GAMES.ACTIONS_MODAL.AMOUNT_PLACEHOLDER')"
          />
        </div>

        <div class="mp-ops">
          <button
            type="button"
            class="mbtn ops-load"
            :disabled="!canSubmit || isSubmitting"
            @click="onLoad"
          >
            {{
              isSubmitting && submitType === 'load'
                ? $t('GAMES.ACTIONS_MODAL.BUSY_ELLIPSIS')
                : $t('GAMES.ACTIONS_MODAL.LOAD_BTN')
            }}
          </button>
          <button
            type="button"
            class="mbtn ops-cash"
            :disabled="!canSubmit || isSubmitting"
            @click="onCashout"
          >
            {{
              isSubmitting && submitType === 'cashout'
                ? $t('GAMES.ACTIONS_MODAL.BUSY_ELLIPSIS')
                : $t('GAMES.ACTIONS_MODAL.CASHOUT_BTN')
            }}
          </button>
        </div>

        <div class="mfield mfield--spaced">
          <label>{{ $t('GAMES.ACTIONS_MODAL.NEW_PASSWORD_LABEL') }}</label>
          <input
            v-model="newPassword"
            type="text"
            :placeholder="$t('GAMES.ACTIONS_MODAL.NEW_PASSWORD_PLACEHOLDER')"
          />
        </div>

        <div class="mp-ops">
          <button
            type="button"
            class="mbtn full"
            :disabled="!username || isResetting"
            @click="onResetPassword"
          >
            {{
              isResetting
                ? $t('GAMES.ACTIONS_MODAL.BUSY_ELLIPSIS')
                : $t('GAMES.ACTIONS_MODAL.RESET_PASSWORD_BTN')
            }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<style lang="scss" scoped>
.overlay {
  --canvas: #050409;
  --surface: #0c0b12;
  --surface-2: #131119;
  --surface-3: #1b1925;
  --border: #171520;
  --border-hi: #2e2940;
  --patra: #6e56cf;
  --patra-deep: #5b45b0;
  --patra-3: #a78bfa;
  --text: #ededf2;
  --text-2: #a8a6b6;
  --text-3: #75727f;
  --text-4: #54515e;
  --green: #3fb950;
  --amber: #e3a008;
  --red: #f85149;
  --blue: #58a6ff;
  --shadow: 0 24px 60px -20px rgba(0, 0, 0, 0.8);

  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.6);
  backdrop-filter: blur(4px);
  z-index: 9999;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 20px;
}

.modal {
  background: var(--surface);
  border: 1px solid var(--border-hi);
  border-radius: 18px;
  width: 480px;
  max-width: 92vw;
  max-height: 88vh;
  overflow-y: auto;
  box-shadow: var(--shadow);
  color: var(--text);
  font-family: 'Inter', sans-serif;
}

.modal-h {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 18px 20px;
  border-bottom: 1px solid var(--border);
  position: sticky;
  top: 0;
  background: var(--surface);
  z-index: 2;

  .mic {
    width: 40px;
    height: 40px;
    border-radius: 11px;
    background: var(--surface-3);
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 21px;
    border: 1px solid var(--border-hi);
  }

  .mt {
    flex: 1;
    min-width: 0;

    .mn {
      font-family: 'Space Grotesk', sans-serif;
      font-weight: 600;
      font-size: 16px;
    }

    .md {
      font-size: 12px;
      color: var(--text-3);
      font-family: 'JetBrains Mono', monospace;
    }
  }
}

.modal-x {
  width: 30px;
  height: 30px;
  border-radius: 8px;
  border: 1px solid var(--border);
  background: var(--surface-2);
  color: var(--text-2);
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: all 0.2s;
  padding: 0;

  &:hover {
    color: #fff;
    background: var(--red);
    border-color: transparent;
    transform: rotate(90deg);
  }
}

.modal-body {
  padding: 20px;
}

.mfield {
  margin-bottom: 13px;

  label {
    display: block;
    font-size: 12px;
    color: var(--text-2);
    margin-bottom: 5px;
  }

  input {
    width: 100%;
    background: var(--canvas);
    border: 1px solid var(--border);
    border-radius: 10px;
    padding: 10px 12px;
    color: var(--text);
    font-size: 13px;
    outline: none;
    transition: all 0.25s;
    font-family: 'JetBrains Mono', monospace;

    &:focus {
      border-color: var(--patra);
      box-shadow: 0 0 0 3px rgba(110, 86, 207, 0.11);
    }
  }

  &--spaced {
    margin-top: 14px;
  }
}

.mp-ops {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 9px;
  margin-top: 6px;
  margin-bottom: 14px;

  &--top {
    margin-bottom: 8px;
  }

  .mbtn {
    width: 100%;
    text-align: center;
  }

  .full {
    grid-column: 1 / -1;
  }
}

.mbtn {
  font-size: 13px;
  font-weight: 600;
  padding: 10px 16px;
  border-radius: 10px;
  border: 1px solid var(--border-hi);
  background: var(--surface-2);
  color: var(--text);
  cursor: pointer;
  transition: all 0.22s;
  font-family: 'Inter', sans-serif;

  &:hover:not(:disabled) {
    transform: translateY(-2px);
    box-shadow: 0 6px 14px rgba(0, 0, 0, 0.3);
  }

  &:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  &.ops-load {
    background: linear-gradient(135deg, var(--green), #2a7f37);
    color: #fff;
    border-color: transparent;
  }

  &.ops-cash {
    background: linear-gradient(135deg, var(--amber), #b8860b);
    color: #fff;
    border-color: transparent;
  }

  &.ops-check {
    color: var(--blue);
    border-color: rgba(88, 166, 255, 0.35);
  }

  &.ops-diag {
    color: var(--patra-3);
    border-color: rgba(167, 139, 250, 0.4);
  }
}

.balance-result {
  display: block;
  font-size: 13px;
  color: var(--green);
  font-family: 'JetBrains Mono', monospace;
  margin-bottom: 14px;
}

.result-banner {
  padding: 10px 14px;
  border-radius: 8px;
  font-size: 13px;
  margin-bottom: 16px;

  &--ok {
    background: rgba(63, 185, 80, 0.12);
    border: 1px solid rgba(63, 185, 80, 0.3);
    color: var(--green);
  }

  &--error {
    background: rgba(248, 81, 73, 0.12);
    border: 1px solid rgba(248, 81, 73, 0.3);
    color: var(--red);
  }
}

.diagnose-block {
  margin-bottom: 14px;
}

.diagnose-pre {
  white-space: pre-wrap;
  margin: 0;
  font-family: 'JetBrains Mono', monospace;
  font-size: 12px;
  color: inherit;
}
</style>
