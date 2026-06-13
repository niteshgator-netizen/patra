<script setup>
// it6 (policy-ui B3) — Agent Policy settings screen. Owner-editable bonus/referral/cashout policy that
// Bella (the AI cashier) reads live (Games::PolicyResolver) as the ONLY source of truth she may state.
// Binds to account.settings['agent_policy'] (validated server-side by AGENT_POLICY_SCHEMA).
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import AgentBonusModal from './AgentBonusModal.vue';
import Button from 'dashboard/components-next/button/Button.vue';

defineOptions({ name: 'AgentPolicySettings' });

const { t } = useI18n();
const store = useStore();
const { currentAccount } = useAccount();

const DAY_LABELS = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];

const emptyPolicy = () => ({
  bonuses: [],
  referral: { percent: null, trigger_deposit_number: 1, cap: null, active: false },
  cashout: {
    min: null,
    max: null,
    playthrough_min: null,
    playthrough_max: null,
    per_platform: {},
    terms_text: '',
    active: false,
  },
});

const policy = ref(emptyPolicy());
const showBonusModal = ref(false);
const editingBonus = ref(null);
const editingIndex = ref(-1);

const uiFlags = computed(() => store.getters['agentPolicy/getAgentPolicyUIFlags']);
const isSaving = computed(() => uiFlags.value.isUpdating);

// hydrate a deep, defensively-defaulted working copy from the saved policy
const loadPolicy = () => {
  const base = emptyPolicy();
  const raw = currentAccount.value?.settings?.agent_policy;
  if (raw && typeof raw === 'object') {
    if (Array.isArray(raw.bonuses)) {
      base.bonuses = JSON.parse(JSON.stringify(raw.bonuses));
    }
    if (raw.referral && typeof raw.referral === 'object') {
      base.referral = { ...base.referral, ...raw.referral };
    }
    if (raw.cashout && typeof raw.cashout === 'object') {
      base.cashout = { ...base.cashout, ...raw.cashout };
      if (!base.cashout.per_platform || typeof base.cashout.per_platform !== 'object') {
        base.cashout.per_platform = {};
      }
    }
  }
  policy.value = base;
};

onMounted(loadPolicy);
watch(currentAccount, loadPolicy);

const scheduleSummary = bonus => {
  const s = bonus.schedule || {};
  if (!s.mode || s.mode === 'always') return t('AGENT_POLICY.BONUS.SCHEDULE.ALWAYS');
  const days = Array.isArray(s.days) && s.days.length
    ? s.days.map(d => DAY_LABELS[d]).filter(Boolean).join(' ')
    : t('AGENT_POLICY.BONUS.SCHEDULE.EVERY_DAY');
  return `${days} · ${s.start_hm || '00:00'}–${s.end_hm || '23:59'}`;
};

// ── bonuses ──────────────────────────────────────────────────────────────────
const addBonus = () => {
  editingBonus.value = null;
  editingIndex.value = -1;
  showBonusModal.value = true;
};
const editBonus = (bonus, index) => {
  editingBonus.value = bonus;
  editingIndex.value = index;
  showBonusModal.value = true;
};
const deleteBonus = index => {
  policy.value.bonuses.splice(index, 1);
};
const onBonusSaved = bonus => {
  if (editingIndex.value >= 0) {
    policy.value.bonuses.splice(editingIndex.value, 1, bonus);
  } else {
    policy.value.bonuses.push(bonus);
  }
  showBonusModal.value = false;
};

// ── cashout per-platform rows ────────────────────────────────────────────────
const platformRows = ref([]);
const syncPlatformRows = () => {
  platformRows.value = Object.entries(policy.value.cashout.per_platform || {}).map(
    ([platform, limits]) => ({
      platform,
      min: limits?.min ?? null,
      max: limits?.max ?? null,
    })
  );
};
watch(policy, syncPlatformRows, { immediate: true });
const addPlatformRow = () => {
  platformRows.value.push({ platform: '', min: null, max: null });
};
const removePlatformRow = index => {
  platformRows.value.splice(index, 1);
};

const num = v => (v === '' || v === null || v === undefined ? null : Number(v));

const buildPayload = () => {
  const p = JSON.parse(JSON.stringify(policy.value));
  // fold per-platform rows back into the object (skip blank platform names)
  const perPlatform = {};
  platformRows.value.forEach(row => {
    const key = (row.platform || '').trim().toLowerCase();
    if (!key) return;
    perPlatform[key] = { min: num(row.min), max: num(row.max) };
  });
  p.cashout.per_platform = perPlatform;
  return p;
};

// ── client validation (percent 0–100, amounts ≥0, end > start) ───────────────
const validate = payload => {
  const errs = [];
  payload.bonuses.forEach((b, i) => {
    const label = b.name || `#${i + 1}`;
    if (b.percent != null && (b.percent < 0 || b.percent > 100)) {
      errs.push(t('AGENT_POLICY.VALIDATION.PERCENT', { name: label }));
    }
    ['min_deposit', 'max_deposit', 'cap'].forEach(k => {
      if (b[k] != null && b[k] < 0) errs.push(t('AGENT_POLICY.VALIDATION.NEGATIVE', { name: label }));
    });
    const s = b.schedule || {};
    if (s.mode === 'window' && s.start_hm && s.end_hm && s.end_hm <= s.start_hm) {
      errs.push(t('AGENT_POLICY.VALIDATION.WINDOW', { name: label }));
    }
  });
  const r = payload.referral || {};
  if (r.percent != null && (r.percent < 0 || r.percent > 100)) {
    errs.push(t('AGENT_POLICY.VALIDATION.REFERRAL_PERCENT'));
  }
  const c = payload.cashout || {};
  ['min', 'max', 'playthrough_min', 'playthrough_max'].forEach(k => {
    if (c[k] != null && c[k] < 0) errs.push(t('AGENT_POLICY.VALIDATION.CASHOUT_NEGATIVE'));
  });
  if (c.min != null && c.max != null && c.max < c.min) {
    errs.push(t('AGENT_POLICY.VALIDATION.CASHOUT_MINMAX'));
  }
  return errs;
};

const save = async () => {
  const payload = buildPayload();
  const errs = validate(payload);
  if (errs.length) {
    useAlert(errs[0]);
    return;
  }
  try {
    await store.dispatch('agentPolicy/updateAgentPolicy', payload);
    useAlert(t('AGENT_POLICY.SAVED'));
  } catch (error) {
    useAlert(error?.message || t('AGENT_POLICY.SAVE_ERROR'));
  }
};
</script>

<template>
  <div
    class="flex flex-col w-full h-full min-h-0 gap-4 p-4 overflow-y-auto md:p-6 text-slate-800 dark:text-slate-100"
  >
    <!-- header -->
    <header class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
      <div>
        <h1 class="text-xl font-semibold">{{ $t('AGENT_POLICY.HEADER') }}</h1>
        <p class="max-w-2xl mt-1 text-sm text-slate-500 dark:text-slate-400">
          {{ $t('AGENT_POLICY.DESCRIPTION') }}
        </p>
      </div>
      <Button :is-loading="isSaving" :disabled="isSaving" @click="save">
        {{ $t('AGENT_POLICY.SAVE') }}
      </Button>
    </header>

    <!-- ── BONUSES ──────────────────────────────────────────────────────── -->
    <section
      class="p-4 border rounded-xl border-slate-100 dark:border-slate-800 bg-white dark:bg-slate-900 md:p-5"
    >
      <div class="flex items-center justify-between mb-3">
        <div>
          <h2 class="text-base font-semibold">{{ $t('AGENT_POLICY.BONUS.TITLE') }}</h2>
          <p class="text-xs text-slate-500 dark:text-slate-400">
            {{ $t('AGENT_POLICY.BONUS.SUBTITLE') }}
          </p>
        </div>
        <Button size="sm" icon="i-lucide-plus" @click="addBonus">
          {{ $t('AGENT_POLICY.BONUS.ADD') }}
        </Button>
      </div>

      <div
        v-if="!policy.bonuses.length"
        class="flex flex-col items-center justify-center gap-2 px-4 py-10 text-center border border-dashed rounded-lg border-slate-200 dark:border-slate-700"
      >
        <span class="text-sm text-slate-500 dark:text-slate-400">
          {{ $t('AGENT_POLICY.BONUS.EMPTY') }}
        </span>
        <Button size="sm" variant="ghost" icon="i-lucide-plus" @click="addBonus">
          {{ $t('AGENT_POLICY.BONUS.ADD_FIRST') }}
        </Button>
      </div>

      <div v-else class="grid grid-cols-1 gap-3 md:grid-cols-2">
        <div
          v-for="(bonus, index) in policy.bonuses"
          :key="bonus.id || index"
          class="flex flex-col gap-2 p-3 border rounded-lg border-slate-100 dark:border-slate-800 bg-slate-50 dark:bg-slate-800/40"
        >
          <div class="flex items-start justify-between gap-2">
            <div class="min-w-0">
              <div class="flex items-center gap-2">
                <span class="font-medium truncate">{{ bonus.name || $t('AGENT_POLICY.BONUS.UNNAMED') }}</span>
                <span
                  class="px-1.5 py-0.5 rounded text-[10px] font-semibold uppercase"
                  :class="bonus.active
                    ? 'bg-green-100 text-green-700 dark:bg-green-900/40 dark:text-green-300'
                    : 'bg-slate-200 text-slate-500 dark:bg-slate-700 dark:text-slate-400'"
                >
                  {{ bonus.active ? $t('AGENT_POLICY.ON') : $t('AGENT_POLICY.OFF') }}
                </span>
              </div>
              <div class="mt-1 text-xs text-slate-500 dark:text-slate-400">
                <span class="font-semibold text-slate-700 dark:text-slate-200">{{ bonus.percent ?? 0 }}%</span>
                · {{ bonus.kind || 'deposit' }}
                <template v-if="bonus.min_deposit != null"> · min ${{ bonus.min_deposit }}</template>
                <template v-if="bonus.cap != null"> · cap ${{ bonus.cap }}</template>
              </div>
              <div class="mt-0.5 text-xs text-slate-400 dark:text-slate-500">{{ scheduleSummary(bonus) }}</div>
            </div>
            <div class="flex items-center gap-1 shrink-0">
              <Button variant="ghost" size="sm" icon="i-lucide-pencil" @click="editBonus(bonus, index)" />
              <Button variant="ghost" color="ruby" size="sm" icon="i-lucide-x" @click="deleteBonus(index)" />
            </div>
          </div>
        </div>
      </div>
    </section>

    <!-- ── REFERRAL ─────────────────────────────────────────────────────── -->
    <section
      class="p-4 border rounded-xl border-slate-100 dark:border-slate-800 bg-white dark:bg-slate-900 md:p-5"
    >
      <div class="flex items-center justify-between mb-3">
        <div>
          <h2 class="text-base font-semibold">{{ $t('AGENT_POLICY.REFERRAL.TITLE') }}</h2>
          <p class="text-xs text-slate-500 dark:text-slate-400">{{ $t('AGENT_POLICY.REFERRAL.SUBTITLE') }}</p>
        </div>
        <label class="flex items-center gap-2 text-sm cursor-pointer">
          <input v-model="policy.referral.active" type="checkbox" class="w-4 h-4" />
          {{ $t('AGENT_POLICY.ACTIVE') }}
        </label>
      </div>
      <div class="grid grid-cols-1 gap-3 sm:grid-cols-3">
        <label class="flex flex-col gap-1 text-sm">
          {{ $t('AGENT_POLICY.REFERRAL.PERCENT') }}
          <input v-model.number="policy.referral.percent" type="number" min="0" max="100" step="0.01" class="ap-input" placeholder="10" />
        </label>
        <label class="flex flex-col gap-1 text-sm">
          {{ $t('AGENT_POLICY.REFERRAL.TRIGGER') }}
          <input v-model.number="policy.referral.trigger_deposit_number" type="number" min="1" step="1" class="ap-input" placeholder="1" />
        </label>
        <label class="flex flex-col gap-1 text-sm">
          {{ $t('AGENT_POLICY.REFERRAL.CAP') }}
          <input v-model.number="policy.referral.cap" type="number" min="0" step="0.01" class="ap-input" :placeholder="$t('AGENT_POLICY.NO_CAP')" />
        </label>
      </div>
    </section>

    <!-- ── CASHOUT ──────────────────────────────────────────────────────── -->
    <section
      class="p-4 border rounded-xl border-slate-100 dark:border-slate-800 bg-white dark:bg-slate-900 md:p-5"
    >
      <div class="flex items-center justify-between mb-3">
        <div>
          <h2 class="text-base font-semibold">{{ $t('AGENT_POLICY.CASHOUT.TITLE') }}</h2>
          <p class="text-xs text-slate-500 dark:text-slate-400">{{ $t('AGENT_POLICY.CASHOUT.SUBTITLE') }}</p>
        </div>
        <label class="flex items-center gap-2 text-sm cursor-pointer">
          <input v-model="policy.cashout.active" type="checkbox" class="w-4 h-4" />
          {{ $t('AGENT_POLICY.ACTIVE') }}
        </label>
      </div>
      <div class="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <label class="flex flex-col gap-1 text-sm">
          {{ $t('AGENT_POLICY.CASHOUT.MIN') }}
          <input v-model.number="policy.cashout.min" type="number" min="0" step="0.01" class="ap-input" placeholder="10" />
        </label>
        <label class="flex flex-col gap-1 text-sm">
          {{ $t('AGENT_POLICY.CASHOUT.MAX') }}
          <input v-model.number="policy.cashout.max" type="number" min="0" step="0.01" class="ap-input" placeholder="500" />
        </label>
        <label class="flex flex-col gap-1 text-sm">
          {{ $t('AGENT_POLICY.CASHOUT.PT_MIN') }}
          <input v-model.number="policy.cashout.playthrough_min" type="number" min="0" step="0.1" class="ap-input" placeholder="1" />
        </label>
        <label class="flex flex-col gap-1 text-sm">
          {{ $t('AGENT_POLICY.CASHOUT.PT_MAX') }}
          <input v-model.number="policy.cashout.playthrough_max" type="number" min="0" step="0.1" class="ap-input" placeholder="3" />
        </label>
      </div>

      <!-- per-platform overrides -->
      <div class="mt-4">
        <div class="flex items-center justify-between mb-2">
          <span class="text-xs font-semibold uppercase text-slate-500 dark:text-slate-400">
            {{ $t('AGENT_POLICY.CASHOUT.PER_PLATFORM') }}
          </span>
          <Button variant="ghost" size="sm" icon="i-lucide-plus" @click="addPlatformRow">
            {{ $t('AGENT_POLICY.CASHOUT.ADD_PLATFORM') }}
          </Button>
        </div>
        <div
          v-for="(row, index) in platformRows"
          :key="index"
          class="grid items-end grid-cols-12 gap-2 mb-2"
        >
          <input v-model="row.platform" type="text" class="col-span-6 sm:col-span-5 ap-input" :placeholder="$t('AGENT_POLICY.CASHOUT.PLATFORM_NAME')" />
          <input v-model.number="row.min" type="number" min="0" step="0.01" class="col-span-3 ap-input" :placeholder="$t('AGENT_POLICY.CASHOUT.MIN')" />
          <input v-model.number="row.max" type="number" min="0" step="0.01" class="col-span-3 ap-input" :placeholder="$t('AGENT_POLICY.CASHOUT.MAX')" />
          <Button variant="ghost" color="ruby" size="sm" icon="i-lucide-x" class="col-span-12 sm:col-span-1" @click="removePlatformRow(index)" />
        </div>
      </div>

      <label class="flex flex-col gap-1 mt-3 text-sm">
        {{ $t('AGENT_POLICY.CASHOUT.TERMS') }}
        <textarea v-model="policy.cashout.terms_text" rows="2" class="ap-input" :placeholder="$t('AGENT_POLICY.CASHOUT.TERMS_PLACEHOLDER')" />
      </label>
    </section>

    <AgentBonusModal
      v-if="showBonusModal"
      :bonus="editingBonus"
      @save="onBonusSaved"
      @close="showBonusModal = false"
    />
  </div>
</template>

<style scoped lang="scss">
.ap-input {
  @apply w-full px-3 py-2 text-sm rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-slate-800 dark:text-slate-100 outline-none transition-colors;

  &:focus {
    @apply border-woot-500 dark:border-woot-400;
  }
}
</style>
