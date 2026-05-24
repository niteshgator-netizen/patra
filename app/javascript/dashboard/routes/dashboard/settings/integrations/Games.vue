<template>
  <div class="games-page">
    <header class="games-page__header">
      <div class="crumb">
        SETTINGS / INTEGRATIONS / <span>GAMES</span>
      </div>
      <h1 class="page-title">{{ $t('GAMES.HEADER') }}</h1>
      <p class="page-subtitle">{{ $t('GAMES.DESCRIPTION') }}</p>
    </header>

    <div class="hint-banner">
      <span class="hint-banner__icon">💡</span>
      <span>{{ $t('GAMES.TIP_BANNER') }}</span>
    </div>

    <div class="stats-row">
      <div class="stat">
        <div class="stat__label">{{ $t('GAMES.STATS.AVAILABLE') }}</div>
        <div class="stat__value">{{ mergedGames.length }}</div>
      </div>
      <div class="stat">
        <div class="stat__label">{{ $t('GAMES.STATS.ACTIVATED') }}</div>
        <div class="stat__value stat__value--accent">{{ activatedCount }}</div>
      </div>
      <div class="stat">
        <div class="stat__label">{{ $t('GAMES.STATS.API_CONNECTED') }}</div>
        <div class="stat__value">{{ apiConnectedCount }}</div>
      </div>
      <div class="stat">
        <div class="stat__label">{{ $t('GAMES.STATS.PENDING_SETUP') }}</div>
        <div class="stat__value">{{ pendingSetupCount }}</div>
      </div>
    </div>

    <div v-if="isLoading" class="loading-state">{{ $t('GAMES.LOADING') }}</div>

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
        const agentGame = this.agentGames.find(ag => ag.game && ag.game.id === game.id);
        return { ...game, agentGame };
      });
    },
    activatedCount() {
      return this.mergedGames.filter(g => g.agentGame?.status === 'active').length;
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
        this.availableGames = (Array.isArray(availablePayload) ? availablePayload : [])
          .filter(g => g && g.has_api)
          .map(mergeGameUiMetadata);
        this.agentGames = Array.isArray(activatedPayload) ? activatedPayload : [];
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
          const newStatus = game.agentGame.status === 'active' ? 'inactive' : 'active';
          await GamesAPI.updateAgentGame(game.agentGame.id, { status: newStatus });
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
  },
};
</script>

<style lang="scss" scoped>
.games-page {
  padding: 24px 28px 80px;
  max-width: 1200px;
  margin: 0 auto;
  color: #f4f1ff;
  font-family: 'Inter', sans-serif;

  &__header {
    margin-bottom: 28px;
  }
}

.crumb {
  font-size: 11px;
  color: #6f6692;
  font-family: 'JetBrains Mono', monospace;
  letter-spacing: 0.05em;
  margin-bottom: 10px;

  span {
    color: #d4af37;
  }
}

.page-title {
  font-family: 'Space Grotesk', sans-serif;
  font-size: 28px;
  font-weight: 700;
  letter-spacing: -0.02em;
  margin-bottom: 6px;
  color: #f4f1ff;
}

.page-subtitle {
  color: #a89fcc;
  font-size: 14px;
  max-width: 600px;
}

.hint-banner {
  background: rgba(212, 175, 55, 0.12);
  border: 1px solid rgba(212, 175, 55, 0.3);
  border-radius: 10px;
  padding: 12px 16px;
  margin-bottom: 24px;
  display: flex;
  align-items: center;
  gap: 12px;
  font-size: 13px;
  color: #d4af37;

  &__icon {
    font-size: 18px;
  }
}

.stats-row {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
  gap: 12px;
  margin-bottom: 28px;
}

.stat {
  padding: 16px;
  background: #16102b;
  border: 1px solid #2d2356;
  border-radius: 12px;

  &__label {
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: #6f6692;
    font-family: 'Space Grotesk', sans-serif;
    font-weight: 600;
    margin-bottom: 6px;
  }

  &__value {
    font-family: 'Space Grotesk', sans-serif;
    font-size: 22px;
    font-weight: 700;
    letter-spacing: -0.02em;

    &--accent {
      color: #d4af37;
    }
  }
}

.games-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(260px, 1fr));
  gap: 16px;
}

.loading-state {
  text-align: center;
  padding: 60px 20px;
  color: #a89fcc;
  font-size: 14px;
}
</style>
