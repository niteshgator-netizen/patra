<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import GamesAPI from 'dashboard/api/games';

const { t } = useI18n();

const LAUNCH_GAMES = [
  { slug: 'juwa', name: 'Juwa' },
  { slug: 'juwa_2', name: 'Juwa 2.0' },
  { slug: 'game_vault', name: 'Game Vault' },
  { slug: 'vegas_sweeps', name: 'Vegas Sweeps' },
  { slug: 'ultra_panda', name: 'Ultra Panda' },
  { slug: 'milky_way', name: 'Milky Way' },
  { slug: 'fire_kirin', name: 'Fire Kirin' },
  { slug: 'panda_master', name: 'Panda Master' },
  { slug: 'orion_stars', name: 'Orion Stars' },
  { slug: 'vblink', name: 'Vblink' },
  { slug: 'mafia', name: 'Mafia' },
  { slug: 'game_room', name: 'Gameroom' },
  { slug: 'cash_machine', name: 'Cash Machine' },
  { slug: 'mr_all_in_one', name: 'Mr All In One' },
];

const agentGamesBySlug = ref({});
const selectedSlug = ref('juwa');
const username = ref('');
const amount = ref(null);
const loading = ref(false);
const actionType = ref(null);
const resultText = ref('');
const resultOk = ref(false);

const selectedAgentGame = computed(
  () => agentGamesBySlug.value[selectedSlug.value]
);

const canSubmitAmount = computed(
  () => username.value.trim() && amount.value && amount.value > 0
);

const setResult = (ok, message) => {
  resultOk.value = ok;
  resultText.value = message;
};

const loadAgentGames = async () => {
  try {
    const { data } = await GamesAPI.get();
    const rows = Array.isArray(data) ? data : [];
    agentGamesBySlug.value = rows.reduce((acc, ag) => {
      const slug = ag.game?.slug;
      if (slug && ag.status === 'active') acc[slug] = ag;
      return acc;
    }, {});
  } catch {
    agentGamesBySlug.value = {};
  }
};

const requireAgentGame = () => {
  if (!selectedAgentGame.value) {
    setResult(false, t('GAMES.QUICK_ACTIONS.NO_ACTIVE_GAME'));
    return false;
  }
  if (!username.value.trim()) {
    setResult(false, t('GAMES.QUICK_ACTIONS.USERNAME_REQUIRED'));
    return false;
  }
  return true;
};

const onCheckBalance = async () => {
  if (!requireAgentGame()) return;
  loading.value = true;
  actionType.value = 'balance';
  try {
    const { data } = await GamesAPI.checkPlayer(
      selectedAgentGame.value.id,
      username.value.trim()
    );
    if (data.ok) {
      setResult(
        true,
        t('GAMES.ACTIONS_MODAL.BALANCE_RESULT', { balance: data.balance })
      );
    } else {
      setResult(false, data.message);
    }
  } catch (err) {
    setResult(false, err.response?.data?.message || 'Check failed');
  } finally {
    loading.value = false;
    actionType.value = null;
  }
};

const onCreate = async () => {
  if (!requireAgentGame()) return;
  loading.value = true;
  actionType.value = 'create';
  try {
    const { data } = await GamesAPI.addPlayer(selectedAgentGame.value.id, {
      game_username: username.value.trim(),
    });
    if (data.ok) {
      const pwd = data.password ? ` password: ${data.password}` : '';
      setResult(
        true,
        `${t('GAMES.QUICK_ACTIONS.CREATE_SUCCESS')} ${username.value}${pwd}`
      );
    } else {
      setResult(false, data.message);
    }
  } catch (err) {
    setResult(false, err.response?.data?.message || 'Create failed');
  } finally {
    loading.value = false;
    actionType.value = null;
  }
};

const onLoad = async () => {
  if (!requireAgentGame() || !canSubmitAmount.value) return;
  loading.value = true;
  actionType.value = 'load';
  try {
    const { data } = await GamesAPI.loadPlayer(selectedAgentGame.value.id, {
      game_username: username.value.trim(),
      amount: amount.value,
    });
    if (data.ok) {
      setResult(
        true,
        t('GAMES.ACTIONS_MODAL.LOAD_SUCCESS', {
          amount: amount.value,
          username: username.value.trim(),
        })
      );
    } else {
      setResult(false, data.message);
    }
  } catch (err) {
    setResult(false, err.response?.data?.message || 'Load failed');
  } finally {
    loading.value = false;
    actionType.value = null;
  }
};

const onRedeem = async () => {
  if (!requireAgentGame() || !canSubmitAmount.value) return;
  loading.value = true;
  actionType.value = 'redeem';
  try {
    const { data } = await GamesAPI.cashoutPlayer(selectedAgentGame.value.id, {
      game_username: username.value.trim(),
      amount: amount.value,
    });
    if (data.ok) {
      setResult(
        true,
        t('GAMES.ACTIONS_MODAL.CASHOUT_SUCCESS', {
          amount: amount.value,
          username: username.value.trim(),
        })
      );
    } else {
      setResult(false, data.message);
    }
  } catch (err) {
    setResult(false, err.response?.data?.message || 'Redeem failed');
  } finally {
    loading.value = false;
    actionType.value = null;
  }
};

const onResetPassword = async () => {
  if (!requireAgentGame()) return;
  loading.value = true;
  actionType.value = 'reset';
  try {
    const { data } = await GamesAPI.resetPlayerPassword(
      selectedAgentGame.value.id,
      { game_username: username.value.trim() }
    );
    if (data.ok) {
      setResult(
        true,
        `${t('GAMES.QUICK_ACTIONS.RESET_SUCCESS')} ${data.new_password || ''}`.trim()
      );
    } else {
      setResult(false, data.message);
    }
  } catch (err) {
    setResult(false, err.response?.data?.message || 'Reset failed');
  } finally {
    loading.value = false;
    actionType.value = null;
  }
};

onMounted(loadAgentGames);
</script>

<template>
  <div>
    <div class="ops-field">
      <label>{{ $t('GAMES.QUICK_ACTIONS.GAME') }}</label>
      <select v-model="selectedSlug" class="ops-select">
        <option
          v-for="game in LAUNCH_GAMES"
          :key="game.slug"
          :value="game.slug"
        >
          {{ game.name }}
        </option>
      </select>
    </div>

    <div class="ops-field">
      <label>{{ $t('GAMES.ACTIONS_MODAL.USERNAME_LABEL') }}</label>
      <input
        v-model="username"
        type="text"
        :placeholder="$t('GAMES.ACTIONS_MODAL.USERNAME_PLACEHOLDER')"
      />
    </div>

    <div class="ops-field">
      <label>{{ $t('GAMES.ACTIONS_MODAL.AMOUNT_LABEL') }}</label>
      <input
        v-model.number="amount"
        type="number"
        min="0"
        step="0.01"
        placeholder=""
      />
    </div>

    <div class="ops-btns">
      <button
        type="button"
        class="ops-btn check"
        :disabled="loading"
        @click="onCheckBalance"
      >
        {{
          actionType === 'balance' && loading
            ? '…'
            : $t('GAMES.ACTIONS_MODAL.CHECK_BALANCE_BTN')
        }}
      </button>
      <button
        type="button"
        class="ops-btn"
        :disabled="loading"
        @click="onCreate"
      >
        {{
          actionType === 'create' && loading
            ? '…'
            : $t('GAMES.QUICK_ACTIONS.CREATE')
        }}
      </button>
      <button
        type="button"
        class="ops-btn load"
        :disabled="loading || !canSubmitAmount"
        @click="onLoad"
      >
        {{
          actionType === 'load' && loading
            ? '…'
            : $t('GAMES.ACTIONS_MODAL.LOAD_BTN')
        }}
      </button>
      <button
        type="button"
        class="ops-btn redeem"
        :disabled="loading || !canSubmitAmount"
        @click="onRedeem"
      >
        {{
          actionType === 'redeem' && loading
            ? '…'
            : $t('GAMES.QUICK_ACTIONS.REDEEM')
        }}
      </button>
      <button
        type="button"
        class="ops-btn"
        :disabled="loading"
        @click="onResetPassword"
      >
        {{
          actionType === 'reset' && loading
            ? '…'
            : $t('GAMES.QUICK_ACTIONS.RESET')
        }}
      </button>
    </div>

    <p
      v-if="resultText"
      class="mt-2 rounded-lg px-2 py-1.5 text-xs"
      :class="resultOk ? 'text-[var(--green)]' : 'text-[var(--red)]'"
    >
      {{ resultText }}
    </p>
  </div>
</template>
