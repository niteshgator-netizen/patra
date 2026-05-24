<template>
  <div class="modal-backdrop" @click.self="$emit('close')">
    <div class="modal">
      <header class="modal__head">
        <div class="modal__title-wrap">
          <div class="game-logo">{{ game.logo_emoji || '🎮' }}</div>
          <div>
            <h3 class="modal__title">
              {{ $t('GAMES.MODAL.TITLE', { gameName: game.name }) }}
            </h3>
            <div class="modal__subtitle">{{ game.domain }}</div>
          </div>
        </div>
        <button type="button" class="modal__close" @click="$emit('close')">✕</button>
      </header>

      <div class="modal__body">
        <div v-if="testResult" class="test-result" :class="testResult.ok ? 'test-result--ok' : 'test-result--error'">
          <span v-if="testResult.ok">✓ {{ testResult.message }}<span v-if="testResult.balance"> · Balance: ${{ testResult.balance }}</span></span>
          <span v-else>✗ {{ testResult.message }}</span>
        </div>
        <div v-if="errorMessage" class="error-banner">{{ errorMessage }}</div>

        <div v-if="game.has_api" class="section">
          <h4 class="section__title">{{ $t('GAMES.MODAL.CREDENTIALS_TAB') }}</h4>
          <div v-for="field in normalizedCredentialFields" :key="field.name" class="field">
            <label class="field__label">{{ field.label }}</label>
            <input
              v-model="credentials[field.name]"
              :type="field.type === 'password' ? 'password' : 'text'"
              class="field__input"
              :placeholder="field.label"
            />
            <div v-if="field.help" class="field__hint">{{ field.help }}</div>
          </div>

          <div class="checkbox-row">
            <input id="ip-whitelist" v-model="ipWhitelistConfirmed" type="checkbox" />
            <label for="ip-whitelist">
              {{ $t('GAMES.MODAL.IP_WHITELIST_LABEL', { gameName: game.name }) }}
            </label>
          </div>
        </div>

        <div v-if="game.has_api" class="section">
          <h4 class="section__title">{{ $t('GAMES.MODAL.LIMITS_TAB') }}</h4>
          <div class="field">
            <label class="field__label">{{ $t('GAMES.MODAL.LOW_BALANCE_THRESHOLD_LABEL') }}</label>
            <input
              v-model="credentials.low_balance_threshold"
              type="number"
              min="0"
              step="1"
              class="field__input"
              :placeholder="$t('GAMES.MODAL.LOW_BALANCE_THRESHOLD_PLACEHOLDER')"
            />
          </div>
          <div class="field">
            <label class="field__label">{{ $t('GAMES.MODAL.MAX_LOAD_AMOUNT_LABEL') }}</label>
            <input
              v-model="credentials.max_load_amount"
              type="number"
              min="0"
              step="0.01"
              class="field__input"
              :placeholder="$t('GAMES.MODAL.MAX_LOAD_AMOUNT_PLACEHOLDER')"
            />
          </div>
          <div class="field">
            <label class="field__label">{{ $t('GAMES.MODAL.MAX_CASHOUT_AMOUNT_LABEL') }}</label>
            <input
              v-model="credentials.max_cashout_amount"
              type="number"
              min="0"
              step="0.01"
              class="field__input"
              :placeholder="$t('GAMES.MODAL.MAX_CASHOUT_AMOUNT_PLACEHOLDER')"
            />
          </div>
        </div>
      </div>

      <footer class="modal__foot">
        <button v-if="agentGame" type="button" class="btn btn--danger" @click="disconnect">
          {{ $t('GAMES.ACTIONS.DISCONNECT') }}
        </button>
        <div class="modal__foot-right">
          <button
            v-if="supportsTestConnection"
            type="button"
            class="btn btn--ghost"
            :disabled="isTesting"
            @click="testConnection"
          >
            {{ isTesting ? $t('GAMES.MODAL.TESTING') : $t('GAMES.ACTIONS.TEST_CONNECTION') }}
          </button>
          <button type="button" class="btn" @click="$emit('close')">
            {{ $t('GAMES.ACTIONS.CANCEL') }}
          </button>
          <button type="button" class="btn btn--primary" :disabled="isSaving" @click="save">
            {{ isSaving ? '…' : $t('GAMES.ACTIONS.SAVE') }}
          </button>
        </div>
      </footer>
    </div>
  </div>
</template>

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
    bootstrapForm() {
      this.errorMessage = '';
      this.testResult = null;
      const defs = this.normalizedCredentialFields;
      const fromAgent =
        this.agentGame?.credentials && typeof this.agentGame.credentials === 'object'
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
      ['low_balance_threshold', 'max_load_amount', 'max_cashout_amount'].forEach((key) => {
        if (creds[key] == null) creds[key] = '';
      });
      this.credentials = creds;
      this.ipWhitelistConfirmed = this.agentGame?.ip_whitelist_confirmed || false;
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
        this.testResult = { ok: false, message: err.response?.data?.message || 'Test failed' };
      } finally {
        this.isTesting = false;
      }
    },
  },
};
</script>

<style lang="scss" scoped>
.modal-backdrop {
  position: fixed;
  inset: 0;
  background: rgba(11, 8, 23, 0.7);
  backdrop-filter: blur(8px);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 9999;
  padding: 20px;
}

.modal {
  background: #16102B !important;
  border: 1px solid #2D2356 !important;
  border-radius: 16px;
  width: 100%;
  max-width: 540px;
  max-height: 90vh;
  display: flex;
  flex-direction: column;
  overflow: hidden;
  color: #F4F1FF !important;
  font-family: 'Inter', sans-serif;

  &__head {
    padding: 20px 24px;
    border-bottom: 1px solid #2D2356;
    display: flex;
    justify-content: space-between;
    align-items: center;
  }

  &__title-wrap {
    display: flex;
    align-items: center;
    gap: 12px;
  }

  &__title {
    font-family: 'Space Grotesk', sans-serif;
    font-size: 18px;
    font-weight: 700;
    margin: 0;
    color: #F4F1FF !important;
  }

  &__subtitle {
    font-size: 12px;
    color: #6F6692 !important;
    font-family: 'JetBrains Mono', monospace;
    margin-top: 2px;
  }

  &__close {
    background: transparent !important;
    border: 1px solid #2D2356 !important;
    color: #A89FCC !important;
    width: 32px;
    height: 32px;
    border-radius: 8px;
    cursor: pointer;
    transition: all 0.15s;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 0;

    &:hover {
      color: #F4F1FF !important;
      border-color: #4A3A8A !important;
    }
  }

  &__body {
    padding: 24px;
    overflow-y: auto;
  }

  &__foot {
    padding: 16px 24px;
    border-top: 1px solid #2D2356;
    display: flex;
    justify-content: space-between;
    align-items: center;
  }

  &__foot-right {
    display: flex;
    gap: 8px;
    margin-left: auto;
  }
}

.game-logo {
  width: 40px;
  height: 40px;
  border-radius: 10px;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 20px;
  background: #1F1740 !important;
  border: 1px solid #2D2356 !important;
}

.section {
  margin-bottom: 24px;

  &__title {
    font-family: 'Space Grotesk', sans-serif;
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: #6F6692 !important;
    margin-bottom: 12px;
    font-weight: 600;
  }
}

.field {
  margin-bottom: 14px;

  &__label {
    display: block;
    font-size: 12px;
    color: #A89FCC !important;
    margin-bottom: 6px;
    font-weight: 500;
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
    box-shadow: none !important;
    margin: 0 !important;
    height: auto !important;

    &::placeholder {
      color: #6F6692 !important;
    }

    &:focus {
      outline: 2px solid #D4AF37 !important;
      border-color: transparent !important;
      background: #1F1740 !important;
      box-shadow: none !important;
    }
  }

  &__textarea {
    font-family: 'Inter', sans-serif !important;
    resize: vertical;
    min-height: 70px;
  }

  &__hint {
    font-size: 11px;
    color: #6F6692 !important;
    margin-top: 4px;
  }
}

.checkbox-row {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 12px 14px;
  background: #1F1740 !important;
  border: 1px solid #2D2356 !important;
  border-radius: 8px;
  font-size: 13px;
  color: #F4F1FF !important;
  margin-bottom: 8px;

  input[type="checkbox"] {
    cursor: pointer;
    width: 16px;
    height: 16px;
    accent-color: #D4AF37;
    margin: 0 !important;
    flex-shrink: 0;
  }

  label {
    cursor: pointer;
    color: #F4F1FF !important;
    margin: 0 !important;
    font-weight: 400;
    line-height: 1.4;
  }
}

.error-banner {
  background: rgba(248, 113, 113, 0.12) !important;
  border: 1px solid rgba(248, 113, 113, 0.3) !important;
  color: #F87171 !important;
  padding: 10px 14px;
  border-radius: 8px;
  font-size: 13px;
  margin-bottom: 16px;
}

.btn {
  font-family: 'Inter', sans-serif !important;
  font-size: 13px !important;
  font-weight: 600 !important;
  padding: 9px 16px !important;
  border-radius: 8px !important;
  border: 1px solid #2D2356 !important;
  background: #1F1740 !important;
  color: #F4F1FF !important;
  cursor: pointer;
  transition: all 0.15s;
  margin: 0 !important;
  height: auto !important;

  &:hover {
    border-color: #4A3A8A !important;
    background: #2D2356 !important;
  }

  &--primary {
    background: #D4AF37 !important;
    color: #0B0817 !important;
    border-color: #D4AF37 !important;

    &:hover {
      background: #B8961F !important;
      border-color: #B8961F !important;
    }

    &:disabled {
      opacity: 0.6 !important;
      cursor: not-allowed;
    }
  }

  &--danger {
    color: #F87171 !important;
    border-color: rgba(248, 113, 113, 0.3) !important;
    background: transparent !important;

    &:hover {
      background: rgba(248, 113, 113, 0.12) !important;
    }
  }
}

.test-result {
  padding: 10px 14px !important;
  border-radius: 8px;
  font-size: 13px;
  margin-bottom: 16px;
  font-family: 'JetBrains Mono', monospace;

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

.btn--ghost {
  background: transparent !important;
  border: 1px solid #2D2356 !important;
  color: #A89FCC !important;

  &:hover {
    color: #F4F1FF !important;
    border-color: #4A3A8A !important;
  }
}
</style>
