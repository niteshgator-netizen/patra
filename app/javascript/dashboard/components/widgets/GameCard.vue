<script>
export default {
  name: 'GameCard',
  props: {
    game: { type: Object, required: true },
    agentGame: { type: Object, default: null },
  },
  emits: ['configure', 'toggle', 'managePlayers'],
  computed: {
    isActive() {
      return this.agentGame?.status === 'active';
    },
    showManagePlayers() {
      return this.isActive && this.agentGame && this.agentGame.api_configured;
    },
  },
  methods: {
    onCardMouseMove(e) {
      const el = e.currentTarget;
      const r = el.getBoundingClientRect();
      el.style.setProperty('--mx', `${e.clientX - r.left}px`);
      el.style.setProperty('--my', `${e.clientY - r.top}px`);
    },
  },
};
</script>

<template>
  <div class="gcard" @mousemove="onCardMouseMove">
    <div class="gcard-top">
      <div class="gcard-ic">{{ game.logo_emoji || '🎮' }}</div>
      <div class="gcard-name">
        <div class="gn">{{ game.name }}</div>
        <div class="gd">{{ game.domain }}</div>
      </div>
      <div
        class="gcard-sw"
        :class="{ off: !isActive }"
        role="button"
        tabindex="0"
        @click.stop="$emit('toggle')"
        @keydown.enter.stop="$emit('toggle')"
      >
        <i />
      </div>
    </div>

    <div class="gcard-badges">
      <span v-if="isActive" class="gbadge active">
        <span class="gdot" />{{ $t('GAMES.STATUS.ACTIVE') }}
      </span>
      <span v-else class="gbadge warn">
        <span class="gdot" />{{ $t('GAMES.STATUS.INACTIVE') }}
      </span>
      <span
        v-if="isActive && agentGame && agentGame.api_configured"
        class="gbadge api"
      >
        <span class="gdot" />{{ $t('GAMES.STATUS.API_CONNECTED') }}
      </span>
      <span v-else-if="isActive && game.has_api" class="gbadge warn">
        <span class="gdot" />{{ $t('GAMES.STATUS.API_PENDING') }}
      </span>
    </div>

    <div class="gcard-btns">
      <button type="button" class="gcard-btn cfg" @click="$emit('configure')">
        {{ $t('GAMES.ACTIONS.CONFIGURE') }}
      </button>
      <button
        v-if="showManagePlayers"
        type="button"
        class="gcard-btn mp"
        @click.stop="$emit('managePlayers')"
      >
        {{ $t('GAMES.CARD_ACTIONS.MANAGE_PLAYERS') }}
      </button>
    </div>
  </div>
</template>

<style lang="scss" scoped>
.gcard {
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
  --text-3: #75727f;
  --green: #3fb950;
  --amber: #e3a008;
  --blue: #58a6ff;

  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 16px;
  padding: 18px;
  position: relative;
  overflow: hidden;
  transition: all 0.3s cubic-bezier(0.34, 1.56, 0.64, 1);

  &::after {
    content: '';
    position: absolute;
    inset: 0;
    background: radial-gradient(
      200px circle at var(--mx, 50%) var(--my, 50%),
      rgba(110, 86, 207, 0.12),
      transparent 70%
    );
    opacity: 0;
    transition: opacity 0.3s;
    pointer-events: none;
  }

  &:hover {
    border-color: var(--patra);
    transform: translateY(-5px);
    box-shadow:
      0 20px 40px -12px rgba(0, 0, 0, 0.55),
      0 0 26px rgba(110, 86, 207, 0.18);

    &::after {
      opacity: 1;
    }
  }
}

.gcard-top {
  display: flex;
  align-items: flex-start;
  gap: 12px;
  margin-bottom: 14px;
}

.gcard-ic {
  width: 48px;
  height: 48px;
  border-radius: 13px;
  background: linear-gradient(135deg, var(--surface-3), var(--surface-2));
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 25px;
  flex-shrink: 0;
  border: 1px solid var(--border-hi);
  transition: transform 0.3s cubic-bezier(0.34, 1.56, 0.64, 1);
}

.gcard:hover .gcard-ic {
  transform: scale(1.1) rotate(-5deg);
}

.gcard-name {
  flex: 1;
  min-width: 0;

  .gn {
    font-family: 'Space Grotesk', sans-serif;
    font-weight: 600;
    font-size: 16px;
    color: var(--text);
  }

  .gd {
    font-size: 12px;
    color: var(--text-3);
    font-family: 'JetBrains Mono', monospace;
    margin-top: 2px;
  }
}

.gcard-sw {
  width: 38px;
  height: 22px;
  border-radius: 12px;
  background: linear-gradient(135deg, var(--patra), var(--patra-2));
  position: relative;
  cursor: pointer;
  flex-shrink: 0;
  box-shadow: 0 0 12px var(--patra-glow);
  transition: all 0.3s;

  i {
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

  &.off {
    background: var(--surface-4);
    box-shadow: none;

    i {
      right: auto;
      left: 2px;
    }
  }
}

.gcard-badges {
  display: flex;
  gap: 7px;
  margin-bottom: 15px;
  flex-wrap: wrap;
}

.gbadge {
  font-size: 10px;
  font-weight: 600;
  padding: 4px 9px;
  border-radius: 7px;
  display: flex;
  align-items: center;
  gap: 4px;
  font-family: 'JetBrains Mono', monospace;
  text-transform: uppercase;

  &.active {
    background: rgba(63, 185, 80, 0.16);
    color: var(--green);
  }

  &.api {
    background: rgba(88, 166, 255, 0.16);
    color: var(--blue);
  }

  &.warn {
    background: rgba(227, 160, 8, 0.16);
    color: var(--amber);
  }

  .gdot {
    width: 6px;
    height: 6px;
    border-radius: 50%;
    background: currentColor;
  }
}

.gcard-btns {
  display: flex;
  gap: 8px;
}

.gcard-btn {
  flex: 1;
  font-size: 12.5px;
  font-weight: 600;
  padding: 9px;
  border-radius: 9px;
  border: 1px solid var(--border-hi);
  background: var(--surface-2);
  color: var(--text);
  cursor: pointer;
  transition: all 0.22s cubic-bezier(0.34, 1.56, 0.64, 1);
  font-family: 'Inter', sans-serif;

  &:hover {
    transform: translateY(-2px);
    box-shadow: 0 6px 14px rgba(0, 0, 0, 0.3);
  }

  &.cfg:hover {
    border-color: var(--patra);
    color: var(--patra-3);
  }

  &.mp {
    background: linear-gradient(
      135deg,
      rgba(110, 86, 207, 0.16),
      rgba(139, 92, 246, 0.06)
    );
    border-color: rgba(139, 92, 246, 0.32);
    color: var(--patra-3);

    &:hover {
      background: linear-gradient(135deg, var(--patra), var(--patra-deep));
      color: #fff;
    }
  }
}
</style>
