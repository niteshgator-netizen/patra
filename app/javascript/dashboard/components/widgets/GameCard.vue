<template>
  <div class="game-card" :class="{ 'is-active': isActive }">
    <div class="game-card__head">
      <div class="game-logo">{{ game.logo_emoji || '🎮' }}</div>
      <div>
        <div class="game-card__name">{{ game.name }}</div>
        <div class="game-card__domain">{{ game.domain }}</div>
      </div>
    </div>

    <div class="game-card__pills">
      <span v-if="isActive" class="pill pill--active">
        {{ $t('GAMES.STATUS.ACTIVE') }}
      </span>
      <span v-else class="pill pill--inactive">
        {{ $t('GAMES.STATUS.INACTIVE') }}
      </span>
      <span v-if="isActive && agentGame && agentGame.api_configured" class="pill pill--api">
        {{ $t('GAMES.STATUS.API_CONNECTED') }}
      </span>
      <span v-else-if="isActive && game.has_api" class="pill pill--pending">
        {{ $t('GAMES.STATUS.API_PENDING') }}
      </span>
    </div>

    <div class="game-card__foot">
      <div class="game-card__foot-left">
        <button class="btn" @click="$emit('configure')">
          {{ $t('GAMES.ACTIONS.CONFIGURE') }}
        </button>
        <button
          v-if="isActive && agentGame && agentGame.api_configured"
          class="btn btn--accent"
          @click.stop="$emit('manage-players')"
        >
          {{ $t('GAMES.CARD_ACTIONS.MANAGE_PLAYERS') }}
        </button>
      </div>
      <div class="toggle-switch" :class="{ on: isActive }" @click.stop="$emit('toggle')"></div>
    </div>
  </div>
</template>

<script>
export default {
  name: 'GameCard',
  props: {
    game: { type: Object, required: true },
    agentGame: { type: Object, default: null },
  },
  emits: ['configure', 'toggle', 'manage-players'],
  computed: {
    isActive() {
      return this.agentGame?.status === 'active';
    },
  },
};
</script>

<style lang="scss" scoped>
.game-card {
  padding: 18px;
  background: #16102b;
  border: 1px solid #2d2356;
  border-radius: 14px;
  transition: all 0.2s;
  position: relative;
  overflow: hidden;

  &:hover {
    border-color: #4a3a8a;
    transform: translateY(-2px);
    box-shadow: 0 12px 24px -8px rgba(0, 0, 0, 0.3);
  }

  &::before {
    content: '';
    position: absolute;
    top: 0;
    left: 0;
    right: 0;
    height: 3px;
    background: #d4af37;
    opacity: 0;
    transition: opacity 0.2s;
  }

  &.is-active::before {
    opacity: 1;
  }

  &__head {
    display: flex;
    align-items: center;
    gap: 12px;
    margin-bottom: 14px;
  }

  &__name {
    font-family: 'Space Grotesk', sans-serif;
    font-size: 15px;
    font-weight: 600;
    color: #f4f1ff;
    margin-bottom: 2px;
  }

  &__domain {
    font-size: 11px;
    color: #6f6692;
    font-family: 'JetBrains Mono', monospace;
  }

  &__pills {
    display: flex;
    gap: 6px;
    margin-bottom: 14px;
    flex-wrap: wrap;
  }

  &__foot {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding-top: 14px;
    border-top: 1px solid #2d2356;
  }
}

.game-logo {
  width: 44px;
  height: 44px;
  border-radius: 10px;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 22px;
  background: #1f1740;
  border: 1px solid #2d2356;
}

.pill {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 3px 9px;
  border-radius: 999px;
  font-size: 10px;
  font-weight: 600;
  letter-spacing: 0.03em;
  text-transform: uppercase;
  font-family: 'Space Grotesk', sans-serif;

  &::before {
    content: '';
    width: 5px;
    height: 5px;
    border-radius: 50%;
    background: currentColor;
  }

  &--active {
    background: rgba(74, 222, 128, 0.12);
    color: #4ade80;
  }

  &--inactive {
    background: #1f1740;
    color: #6f6692;
  }

  &--api {
    background: rgba(167, 139, 250, 0.12);
    color: #a78bfa;
  }

  &--pending {
    background: rgba(251, 191, 36, 0.12);
    color: #fbbf24;
  }
}

.btn {
  font-family: 'Inter', sans-serif;
  font-size: 12px;
  font-weight: 600;
  padding: 7px 13px;
  border-radius: 7px;
  border: 1px solid #2d2356;
  background: #1f1740;
  color: #f4f1ff;
  cursor: pointer;
  transition: all 0.15s;

  &:hover {
    border-color: #4a3a8a;
    background: #2d2356;
  }
}

.toggle-switch {
  position: relative;
  width: 34px;
  height: 18px;
  background: #1f1740;
  border-radius: 999px;
  cursor: pointer;
  transition: background 0.2s;
  border: 1px solid #2d2356;
  padding: 0;

  &::after {
    content: '';
    position: absolute;
    top: 1px;
    left: 1px;
    width: 14px;
    height: 14px;
    border-radius: 50%;
    background: #a89fcc;
    transition: all 0.2s;
  }

  &.on {
    background: #d4af37;
    border-color: #d4af37;
  }

  &.on::after {
    left: 17px;
    background: #0b0817;
  }
}

.game-card__foot-left {
  display: flex;
  gap: 6px;
}

.btn--accent {
  background: rgba(212, 175, 55, 0.12) !important;
  color: #d4af37 !important;
  border-color: rgba(212, 175, 55, 0.3) !important;

  &:hover {
    background: rgba(212, 175, 55, 0.18) !important;
    border-color: #d4af37 !important;
  }
}
</style>
