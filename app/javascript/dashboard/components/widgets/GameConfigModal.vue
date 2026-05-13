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
        <div v-if="errorMessage" class="error-banner">{{ errorMessage }}</div>

        <div v-if="game.has_api" class="section">
          <h4 class="section__title">{{ $t('GAMES.MODAL.CREDENTIALS_TAB') }}</h4>
          <div v-for="field in requiredFields" :key="field.name" class="field">
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

        <div class="section">
          <div class="field">
            <label class="field__label">{{ $t('GAMES.MODAL.DISPLAY_NAME_LABEL') }}</label>
            <input v-model="displayName" type="text" class="field__input" :placeholder="game.name" />
            <div class="field__hint">{{ $t('GAMES.MODAL.DISPLAY_NAME_HELP') }}</div>
          </div>

          <div class="field">
            <label class="field__label">{{ $t('GAMES.MODAL.NOTES_LABEL') }}</label>
            <textarea v-model="notes" class="field__input field__textarea" rows="3" />
          </div>
        </div>
      </div>

      <footer class="modal__foot">
        <button v-if="agentGame" type="button" class="btn btn--danger" @click="disconnect">
          {{ $t('GAMES.ACTIONS.DISCONNECT') }}
        </button>
        <div class="modal__foot-right">
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
      displayName: '',
      notes: '',
      ipWhitelistConfirmed: false,
      isSaving: false,
      errorMessage: '',
    };
  },
  computed: {
    requiredFields() {
      return Array.isArray(this.game.required_fields) ? this.game.required_fields : [];
    },
  },
  mounted() {
    if (this.agentGame) {
      this.credentials = { ...(this.agentGame.credentials || {}) };
      this.displayName = this.agentGame.display_name || '';
      this.notes = this.agentGame.notes || '';
      this.ipWhitelistConfirmed = this.agentGame.ip_whitelist_confirmed || false;
    }
  },
  methods: {
    async save() {
      this.isSaving = true;
      this.errorMessage = '';
      try {
        if (this.agentGame) {
          await GamesAPI.updateAgentGame(this.agentGame.id, {
            credentials: this.credentials,
            display_name: this.displayName,
            notes: this.notes,
            ip_whitelist_confirmed: this.ipWhitelistConfirmed,
            status: 'active',
          });
        } else {
          await GamesAPI.activate({
            gameId: this.game.id,
            credentials: this.credentials,
            displayName: this.displayName,
            notes: this.notes,
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
  z-index: 1000;
  padding: 20px;
}

.modal {
  background: #16102b;
  border: 1px solid #2d2356;
  border-radius: 16px;
  width: 100%;
  max-width: 540px;
  max-height: 90vh;
  display: flex;
  flex-direction: column;
  overflow: hidden;
  color: #f4f1ff;
  font-family: 'Inter', sans-serif;

  &__head {
    padding: 20px 24px;
    border-bottom: 1px solid #2d2356;
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
  }

  &__subtitle {
    font-size: 12px;
    color: #6f6692;
    font-family: 'JetBrains Mono', monospace;
    margin-top: 2px;
  }

  &__close {
    background: transparent;
    border: 1px solid #2d2356;
    color: #a89fcc;
    width: 32px;
    height: 32px;
    border-radius: 8px;
    cursor: pointer;
    transition: all 0.15s;

    &:hover {
      color: #f4f1ff;
      border-color: #4a3a8a;
    }
  }

  &__body {
    padding: 24px;
    overflow-y: auto;
  }

  &__foot {
    padding: 16px 24px;
    border-top: 1px solid #2d2356;
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
  background: #1f1740;
  border: 1px solid #2d2356;
}

.section {
  margin-bottom: 24px;

  &__title {
    font-family: 'Space Grotesk', sans-serif;
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: #6f6692;
    margin-bottom: 12px;
    font-weight: 600;
  }
}

.field {
  margin-bottom: 14px;

  &__label {
    display: block;
    font-size: 12px;
    color: #a89fcc;
    margin-bottom: 6px;
    font-weight: 500;
  }

  &__input {
    width: 100%;
    background: #1f1740;
    border: 1px solid #2d2356;
    border-radius: 8px;
    padding: 9px 12px;
    color: #f4f1ff;
    font-size: 13px;
    font-family: 'JetBrains Mono', monospace;

    &:focus {
      outline: 2px solid #d4af37;
      border-color: transparent;
    }
  }

  &__textarea {
    font-family: 'Inter', sans-serif;
    resize: vertical;
  }

  &__hint {
    font-size: 11px;
    color: #6f6692;
    margin-top: 4px;
  }
}

.checkbox-row {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 10px 12px;
  background: #1f1740;
  border-radius: 8px;
  font-size: 13px;

  input[type='checkbox'] {
    cursor: pointer;
  }

  label {
    cursor: pointer;
  }
}

.error-banner {
  background: rgba(248, 113, 113, 0.12);
  border: 1px solid rgba(248, 113, 113, 0.3);
  color: #f87171;
  padding: 10px 14px;
  border-radius: 8px;
  font-size: 13px;
  margin-bottom: 16px;
}

.btn {
  font-family: 'Inter', sans-serif;
  font-size: 13px;
  font-weight: 600;
  padding: 9px 16px;
  border-radius: 8px;
  border: 1px solid #2d2356;
  background: #1f1740;
  color: #f4f1ff;
  cursor: pointer;
  transition: all 0.15s;

  &:hover {
    border-color: #4a3a8a;
    background: #2d2356;
  }

  &--primary {
    background: #d4af37;
    color: #0b0817;
    border-color: #d4af37;

    &:hover {
      background: #b8961f;
      border-color: #b8961f;
    }

    &:disabled {
      opacity: 0.6;
      cursor: not-allowed;
    }
  }

  &--danger {
    color: #f87171;
    border-color: rgba(248, 113, 113, 0.3);

    &:hover {
      background: rgba(248, 113, 113, 0.12);
    }
  }
}
</style>
