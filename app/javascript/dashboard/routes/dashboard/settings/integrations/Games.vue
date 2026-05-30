<script>
import GamesAPI from '../../../../api/games';
import GameCard from '../../../../components/widgets/GameCard.vue';
import GameConfigModal from '../../../../components/widgets/GameConfigModal.vue';
import GamePlayerActionsModal from '../../../../components/widgets/GamePlayerActionsModal.vue';
import { mergeGameUiMetadata } from '../../../../helper/gameCredentialUi';
import { useAlert } from 'dashboard/composables';

export default {
  name: 'GamesSettings',
  components: { GameCard, GameConfigModal, GamePlayerActionsModal },
  data() {
    return {
      availableGames: [],
      agentGames: [],
      isLoading: true,
      selectedGame: null,
      selectedPlayerActionsGame: null,
    };
  },
  computed: {
    mergedGames() {
      return this.availableGames.map(game => {
        const agentGame = this.agentGames.find(
          ag => ag.game && ag.game.id === game.id
        );
        return { ...game, agentGame };
      });
    },
    activatedCount() {
      return this.mergedGames.filter(g => g.agentGame?.status === 'active')
        .length;
    },
    apiConnectedCount() {
      return this.mergedGames.filter(g => g.agentGame?.api_configured).length;
    },
    pendingSetupCount() {
      return this.mergedGames.filter(
        g => g.agentGame?.status === 'active' && !g.agentGame?.api_configured
      ).length;
    },
  },
  mounted() {
    this.loadData();
  },
  methods: {
    async loadData() {
      this.isLoading = true;
      try {
        const [availableRes, activatedRes] = await Promise.all([
          GamesAPI.availableGames(),
          GamesAPI.get(),
        ]);
        const availablePayload = availableRes.data;
        const activatedPayload = activatedRes.data;
        this.availableGames = (
          Array.isArray(availablePayload) ? availablePayload : []
        )
          .filter(g => g && g.has_api)
          .map(mergeGameUiMetadata);
        this.agentGames = Array.isArray(activatedPayload)
          ? activatedPayload
          : [];
      } catch {
        useAlert(this.$t('GAMES.TOAST.ERROR'));
      } finally {
        this.isLoading = false;
      }
    },
    openConfigModal(game) {
      this.selectedGame = game;
    },
    closeConfigModal() {
      this.selectedGame = null;
    },
    openPlayerActions(game) {
      this.selectedPlayerActionsGame = game;
    },
    closePlayerActions() {
      this.selectedPlayerActionsGame = null;
    },
    async toggleGameStatus(game) {
      try {
        if (game.agentGame) {
          const newStatus =
            game.agentGame.status === 'active' ? 'inactive' : 'active';
          await GamesAPI.updateAgentGame(game.agentGame.id, {
            status: newStatus,
          });
        } else {
          await GamesAPI.activate({ gameId: game.id, status: 'active' });
        }
        await this.loadData();
      } catch {
        useAlert(this.$t('GAMES.TOAST.ERROR'));
      }
    },
    onAgentGameSaved() {
      this.closeConfigModal();
      this.loadData();
      useAlert(this.$t('GAMES.TOAST.UPDATED'));
    },
    onAgentGameDisconnected() {
      this.closeConfigModal();
      this.loadData();
      useAlert(this.$t('GAMES.TOAST.DEACTIVATED'));
    },
    onSpotlightMove(e) {
      const el = this.$refs.spotlight;
      if (!el) return;
      el.style.left = `${e.clientX}px`;
      el.style.top = `${e.clientY}px`;
      el.style.opacity = '1';
    },
    onSpotlightLeave() {
      const el = this.$refs.spotlight;
      if (el) el.style.opacity = '0';
    },
  },
};
</script>

<template>
  <div
    class="games-wrap"
    @mousemove="onSpotlightMove"
    @mouseleave="onSpotlightLeave"
  >
    <div id="spotlight" ref="spotlight" />
    <div class="mesh" />

    <div class="games-main">
      <div class="topbar">
        <div>
          <h1 class="display">{{ $t('GAMES.HEADER') }}</h1>
          <div class="sub">{{ $t('GAMES.DESCRIPTION') }}</div>
        </div>
      </div>

      <div class="content">
        <div class="gsum">
          <div class="gsum-card">
            <div class="n">{{ mergedGames.length }}</div>
            <div class="l">{{ $t('GAMES.STATS.AVAILABLE') }}</div>
          </div>
          <div class="gsum-card">
            <div class="n p">{{ activatedCount }}</div>
            <div class="l">{{ $t('GAMES.STATS.ACTIVATED') }}</div>
          </div>
          <div class="gsum-card">
            <div class="n g">{{ apiConnectedCount }}</div>
            <div class="l">{{ $t('GAMES.STATS.API_CONNECTED') }}</div>
          </div>
          <div class="gsum-card">
            <div class="n">{{ pendingSetupCount }}</div>
            <div class="l">{{ $t('GAMES.STATS.PENDING_SETUP') }}</div>
          </div>
        </div>

        <div class="callout">
          <svg
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
          >
            <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z" />
          </svg>
          <span>{{ $t('GAMES.TIP_BANNER') }}</span>
        </div>

        <div v-if="isLoading" class="loading-state">
          {{ $t('GAMES.LOADING') }}
        </div>

        <div v-else class="games-grid">
          <GameCard
            v-for="game in mergedGames"
            :key="game.slug"
            :game="game"
            :agent-game="game.agentGame"
            @configure="openConfigModal(game)"
            @toggle="toggleGameStatus(game)"
            @manage-players="openPlayerActions(game)"
          />
        </div>
      </div>
    </div>

    <GameConfigModal
      v-if="selectedGame"
      :game="selectedGame"
      :agent-game="selectedGame.agentGame"
      @close="closeConfigModal"
      @saved="onAgentGameSaved"
      @disconnected="onAgentGameDisconnected"
    />

    <GamePlayerActionsModal
      v-if="selectedPlayerActionsGame"
      :game="selectedPlayerActionsGame"
      :agent-game="selectedPlayerActionsGame.agentGame"
      @close="closePlayerActions"
    />
  </div>
</template>

<style lang="scss" scoped>
.games-wrap {
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

  &::before,
  &::after {
    content: '';
    position: absolute;
    border-radius: 50%;
    filter: blur(100px);
  }

  &::before {
    top: -15%;
    right: -5%;
    width: 700px;
    height: 560px;
    background:
      radial-gradient(circle at 40% 40%, var(--mesh-1), transparent 60%),
      radial-gradient(circle at 70% 70%, var(--mesh-2), transparent 60%);
    animation: meshA 22s ease-in-out infinite alternate;
  }

  &::after {
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

.games-main {
  position: relative;
  z-index: 1;
  padding: 22px 30px 60px;
  max-width: 1200px;
  margin: 0 auto;
}

.topbar {
  margin-bottom: 22px;

  h1.display {
    font-family: 'Space Grotesk', sans-serif;
    font-weight: 600;
    font-size: 26px;
    letter-spacing: -0.02em;
    margin: 0;
  }

  .sub {
    font-size: 13px;
    color: var(--text-3);
    margin-top: 3px;
    max-width: 640px;
  }
}

.gsum {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 14px;
  margin-bottom: 20px;
}

.gsum-card {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 14px;
  padding: 16px 18px;
  position: relative;
  overflow: hidden;
  transition: all 0.3s cubic-bezier(0.34, 1.56, 0.64, 1);

  &:hover {
    border-color: var(--patra);
    transform: translateY(-4px);
    box-shadow:
      0 16px 32px -10px rgba(0, 0, 0, 0.5),
      0 0 22px rgba(110, 86, 207, 0.2);
  }

  .n {
    font-family: 'Space Grotesk', sans-serif;
    font-weight: 700;
    font-size: 28px;

    &.g {
      color: var(--green);
    }

    &.p {
      background: linear-gradient(135deg, var(--patra-2), var(--patra-3));
      -webkit-background-clip: text;
      background-clip: text;
      -webkit-text-fill-color: transparent;
    }
  }

  .l {
    font-size: 11px;
    color: var(--text-3);
    text-transform: uppercase;
    letter-spacing: 0.05em;
    font-family: 'JetBrains Mono', monospace;
    margin-top: 4px;
  }
}

.callout {
  display: flex;
  align-items: center;
  gap: 10px;
  background: linear-gradient(135deg, rgba(227, 160, 8, 0.1), transparent);
  border: 1px solid rgba(227, 160, 8, 0.25);
  border-radius: 12px;
  padding: 11px 15px;
  font-size: 13px;
  color: var(--text-2);
  margin-bottom: 20px;

  svg {
    width: 16px;
    height: 16px;
    color: var(--amber);
    flex-shrink: 0;
  }
}

.games-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
  gap: 14px;
}

.loading-state {
  text-align: center;
  padding: 60px 20px;
  color: var(--text-3);
  font-size: 14px;
}

@media (max-width: 1100px) {
  .gsum {
    grid-template-columns: repeat(2, 1fr);
  }
}

@media (prefers-reduced-motion: reduce) {
  .mesh::before,
  .mesh::after {
    animation: none !important;
  }
}
</style>
