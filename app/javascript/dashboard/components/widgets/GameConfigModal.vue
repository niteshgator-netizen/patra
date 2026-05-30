<script>
import GamesAPI from '../../api/games';
import { useAlert } from 'dashboard/composables';
import { normalizeGameCredentialFields } from 'dashboard/helper/gameCredentialUi';

export default {
  name: 'GameConfigModal',
  props: {
    game: { type: Object, required: true },
    agentGame: { type: Object, default: null },
  },
  emits: ['close', 'saved', 'disconnected'],
  data() {
    return {
      credentials: {},
      ipWhitelistConfirmed: false,
      isSaving: false,
      errorMessage: '',
      isTesting: false,
      testResult: null,
      providerIps: ['184.169.168.179', '18.144.142.102', '172.59.194.86'],
    };
  },
  computed: {
    normalizedCredentialFields() {
      return normalizeGameCredentialFields(this.game);
    },
    /** Prefer API `has_registry_client` (Games::ClientRegistry); fall back to has_api-only for older payloads. */
    supportsTestConnection() {
      const g = this.agentGame?.game || this.game;
      if (!this.agentGame || !g?.has_api) return false;
      if (g.has_registry_client === false) return false;
      return true;
    },
  },
  watch: {
    'game.id'() {
      this.bootstrapForm();
    },
  },
  mounted() {
    this.bootstrapForm();
  },
  methods: {
    copyProviderIps() {
      navigator.clipboard.writeText(this.providerIps.join('\n'));
      useAlert(this.$t('GAMES.MODAL.IPS_COPIED'));
    },
    bootstrapForm() {
      this.errorMessage = '';
      this.testResult = null;
      const defs = this.normalizedCredentialFields;
      const fromAgent =
        this.agentGame?.credentials &&
        typeof this.agentGame.credentials === 'object'
          ? { ...this.agentGame.credentials }
          : {};
      const creds = { ...fromAgent };
      defs.forEach(({ name }) => {
        if (creds[name] == null || creds[name] === '') {
          if (name === 'api_base_url' && this.game.api_base_url) {
            creds[name] = this.game.api_base_url;
          } else {
            creds[name] = creds[name] || '';
          }
        }
      });
      [
        'low_balance_threshold',
        'max_load_amount',
        'max_cashout_amount',
      ].forEach(key => {
        if (creds[key] == null) creds[key] = '';
      });
      this.credentials = creds;
      this.ipWhitelistConfirmed =
        this.agentGame?.ip_whitelist_confirmed || false;
    },
    async save() {
      this.isSaving = true;
      this.errorMessage = '';
      try {
        const trimmedCredentials = Object.fromEntries(
          Object.entries(this.credentials).map(([key, value]) => [
            key,
            typeof value === 'string' ? value.trim() : value,
          ])
        );
        if (this.agentGame) {
          await GamesAPI.updateAgentGame(this.agentGame.id, {
            credentials: trimmedCredentials,
            ip_whitelist_confirmed: this.ipWhitelistConfirmed,
            status: 'active',
          });
        } else {
          await GamesAPI.activate({
            gameId: this.game.id,
            credentials: trimmedCredentials,
            ipWhitelistConfirmed: this.ipWhitelistConfirmed,
            status: 'active',
          });
        }
        this.$emit('saved');
      } catch (err) {
        const errors = err.response?.data?.errors;
        this.errorMessage = Array.isArray(errors)
          ? errors.join(', ')
          : this.$t('GAMES.TOAST.ERROR');
      } finally {
        this.isSaving = false;
      }
    },
    async disconnect() {
      const confirmed = window.confirm(
        this.$t('GAMES.MODAL.DELETE_CONFIRM', { gameName: this.game.name })
      );
      if (!confirmed) return;
      try {
        await GamesAPI.remove(this.agentGame.id);
        this.$emit('disconnected');
      } catch {
        useAlert(this.$t('GAMES.TOAST.ERROR'));
      }
    },
    async testConnection() {
      if (!this.agentGame) return;
      this.isTesting = true;
      this.testResult = null;
      try {
        const response = await GamesAPI.testConnection(this.agentGame.id);
        this.testResult = response.data;
      } catch (err) {
        this.testResult = {
          ok: false,
          message: err.response?.data?.message || 'Test failed',
        };
      } finally {
        this.isTesting = false;
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
            {{ $t('GAMES.MODAL.TITLE', { gameName: game.name }) }}
          </div>
          <div class="md">{{ game.domain }}</div>
        </div>
        <button type="button" class="modal-x" @click="$emit('close')">
          {{ $t('GAMES.ACTIONS.CLOSE_ICON') }}
        </button>
      </div>

      <div class="modal-body">
        <div
          v-if="testResult"
          class="test-result"
          :class="testResult.ok ? 'test-result--ok' : 'test-result--error'"
        >
          <span v-if="testResult.ok">
            {{
              testResult.balance != null
                ? $t('GAMES.MODAL.TEST_OK_WITH_BALANCE', {
                    message: testResult.message,
                    balance: testResult.balance,
                  })
                : $t('GAMES.MODAL.TEST_OK', { message: testResult.message })
            }}
          </span>
          <span v-else>
            {{ $t('GAMES.MODAL.TEST_FAIL', { message: testResult.message }) }}
          </span>
        </div>
        <div v-if="errorMessage" class="error-banner">{{ errorMessage }}</div>

        <template v-if="game.has_api">
          <div class="msec-label">{{ $t('GAMES.MODAL.CREDENTIALS_TAB') }}</div>
          <div
            v-for="field in normalizedCredentialFields"
            :key="field.name"
            class="mfield"
          >
            <label>{{ field.label }}</label>
            <input
              v-model="credentials[field.name]"
              :type="field.type === 'password' ? 'password' : 'text'"
              :placeholder="field.label"
            />
            <div v-if="field.help" class="hint">{{ field.help }}</div>
          </div>

          <div class="msec-label">
            {{ $t('GAMES.MODAL.IP_WHITELIST_REQUIRED') }}
          </div>
          <div class="hint ip-hint">
            {{ $t('GAMES.MODAL.IP_WHITELIST_HELP', { gameName: game.name }) }}
          </div>
          <div class="iplist">
            <div v-for="ip in providerIps" :key="ip" class="iprow">
              {{ ip }}
            </div>
            <button type="button" class="ipcopy" @click="copyProviderIps">
              {{ $t('GAMES.MODAL.COPY_IPS') }}
            </button>
          </div>
          <div
            class="ipcheck"
            :class="{ on: ipWhitelistConfirmed }"
            role="button"
            tabindex="0"
            @click="ipWhitelistConfirmed = !ipWhitelistConfirmed"
            @keydown.enter="ipWhitelistConfirmed = !ipWhitelistConfirmed"
          >
            <span class="cb">{{ $t('GAMES.ACTIONS.CHECK_ICON') }}</span>
            {{ $t('GAMES.MODAL.IP_WHITELIST_LABEL', { gameName: game.name }) }}
          </div>

          <div class="msec-label">{{ $t('GAMES.MODAL.LIMITS_TAB') }}</div>
          <div class="m3">
            <div class="mfield">
              <label>{{ $t('GAMES.MODAL.LOW_BALANCE_THRESHOLD_LABEL') }}</label>
              <input
                v-model="credentials.low_balance_threshold"
                type="number"
                min="0"
                step="1"
                :placeholder="
                  $t('GAMES.MODAL.LOW_BALANCE_THRESHOLD_PLACEHOLDER')
                "
              />
            </div>
            <div class="mfield">
              <label>{{ $t('GAMES.MODAL.MAX_LOAD_AMOUNT_LABEL') }}</label>
              <input
                v-model="credentials.max_load_amount"
                type="number"
                min="0"
                step="0.01"
                :placeholder="$t('GAMES.MODAL.MAX_LOAD_AMOUNT_PLACEHOLDER')"
              />
            </div>
            <div class="mfield">
              <label>{{ $t('GAMES.MODAL.MAX_CASHOUT_AMOUNT_LABEL') }}</label>
              <input
                v-model="credentials.max_cashout_amount"
                type="number"
                min="0"
                step="0.01"
                :placeholder="$t('GAMES.MODAL.MAX_CASHOUT_AMOUNT_PLACEHOLDER')"
              />
            </div>
          </div>
        </template>
      </div>

      <div class="modal-foot">
        <button
          v-if="agentGame"
          type="button"
          class="mbtn danger left"
          @click="disconnect"
        >
          {{ $t('GAMES.ACTIONS.DISCONNECT') }}
        </button>
        <button
          v-if="supportsTestConnection"
          type="button"
          class="mbtn test"
          :disabled="isTesting"
          @click="testConnection"
        >
          {{
            isTesting
              ? $t('GAMES.MODAL.TESTING')
              : $t('GAMES.ACTIONS.TEST_CONNECTION')
          }}
        </button>
        <button
          type="button"
          class="mbtn primary"
          :disabled="isSaving"
          @click="save"
        >
          {{ isSaving ? $t('GAMES.MODAL.SAVING') : $t('GAMES.ACTIONS.SAVE') }}
        </button>
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
  --surface-4: #252233;
  --border: #171520;
  --border-hi: #2e2940;
  --patra: #6e56cf;
  --patra-deep: #5b45b0;
  --patra-3: #a78bfa;
  --patra-glow: rgba(110, 86, 207, 0.55);
  --text: #ededf2;
  --text-2: #a8a6b6;
  --text-3: #75727f;
  --text-4: #54515e;
  --green: #3fb950;
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

.msec-label {
  font-size: 11px;
  font-weight: 600;
  color: var(--text-3);
  text-transform: uppercase;
  letter-spacing: 0.06em;
  font-family: 'JetBrains Mono', monospace;
  margin: 18px 0 11px;

  &:first-child {
    margin-top: 0;
  }
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

  .hint {
    font-size: 11px;
    color: var(--text-4);
    margin-top: 4px;
  }
}

.ip-hint {
  margin-bottom: 8px;
}

.iplist {
  background: var(--canvas);
  border: 1px solid var(--border);
  border-radius: 10px;
  padding: 12px;
}

.iprow {
  display: flex;
  align-items: center;
  justify-content: space-between;
  font-family: 'JetBrains Mono', monospace;
  font-size: 12.5px;
  padding: 4px 0;
  color: var(--text-2);
}

.ipcopy {
  font-size: 11px;
  color: var(--patra-3);
  cursor: pointer;
  margin-top: 8px;
  display: inline-block;
  background: none;
  border: none;
  padding: 0;
  font-family: inherit;

  &:hover {
    text-decoration: underline;
  }
}

.ipcheck {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 12.5px;
  color: var(--text-2);
  margin-top: 12px;
  cursor: pointer;

  .cb {
    width: 18px;
    height: 18px;
    border-radius: 5px;
    border: 1.5px solid var(--border-hi);
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 11px;
    color: transparent;
    transition: all 0.2s;
    flex-shrink: 0;
  }

  &.on .cb {
    background: linear-gradient(135deg, var(--green), #2a7f37);
    border-color: transparent;
    color: #fff;
  }
}

.m3 {
  display: grid;
  grid-template-columns: 1fr 1fr 1fr;
  gap: 9px;

  .mfield {
    margin-bottom: 0;
  }
}

.modal-foot {
  display: flex;
  gap: 9px;
  padding: 16px 20px;
  border-top: 1px solid var(--border);
  position: sticky;
  bottom: 0;
  background: var(--surface);

  .left {
    margin-right: auto;
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
    opacity: 0.6;
    cursor: not-allowed;
  }

  &.primary {
    background: linear-gradient(135deg, var(--patra), var(--patra-deep));
    border-color: transparent;
    color: #fff;
    box-shadow: 0 3px 12px var(--patra-glow);

    &:hover:not(:disabled) {
      filter: brightness(1.12);
    }
  }

  &.danger {
    color: var(--red);
    border-color: rgba(248, 81, 73, 0.3);

    &:hover {
      background: var(--red);
      color: #fff;
      border-color: transparent;
    }
  }

  &.test {
    color: var(--blue);
    border-color: rgba(88, 166, 255, 0.3);
  }
}

.test-result {
  padding: 10px 14px;
  border-radius: 8px;
  font-size: 13px;
  margin-bottom: 16px;
  font-family: 'JetBrains Mono', monospace;

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

.error-banner {
  background: rgba(248, 81, 73, 0.12);
  border: 1px solid rgba(248, 81, 73, 0.3);
  color: var(--red);
  padding: 10px 14px;
  border-radius: 8px;
  font-size: 13px;
  margin-bottom: 16px;
}
</style>
