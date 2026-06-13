<script setup>
// it6 (policy-ui B3) — bonus editor modal. Agent-defined NAME + SCHEDULE (always vs time-window with a
// day picker). Emits a fully-shaped bonus object that the resolver evaluates live. Client-validates
// percent 0–100, amounts ≥ 0, and end > start for windows.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Modal from 'dashboard/components/Modal.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  bonus: { type: Object, default: null },
});
const emit = defineEmits(['save', 'close']);

const { t } = useI18n();

const DAYS = [
  { v: 0, label: 'Su' },
  { v: 1, label: 'Mo' },
  { v: 2, label: 'Tu' },
  { v: 3, label: 'We' },
  { v: 4, label: 'Th' },
  { v: 5, label: 'Fr' },
  { v: 6, label: 'Sa' },
];
const KINDS = ['signup', 'deposit', 'custom'];

const genId = () => `b_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 7)}`;

const blank = () => ({
  id: genId(),
  name: '',
  kind: 'deposit',
  percent: null,
  min_deposit: null,
  max_deposit: null,
  cap: null,
  schedule: { mode: 'always', days: [], start_hm: '18:00', end_hm: '23:00' },
  active: true,
});

const form = ref(
  props.bonus
    ? (() => {
        const b = JSON.parse(JSON.stringify(props.bonus));
        b.id = b.id || genId();
        b.schedule = b.schedule && typeof b.schedule === 'object'
          ? { mode: 'always', days: [], start_hm: '18:00', end_hm: '23:00', ...b.schedule }
          : { mode: 'always', days: [], start_hm: '18:00', end_hm: '23:00' };
        if (!Array.isArray(b.schedule.days)) b.schedule.days = [];
        return b;
      })()
    : blank()
);

const show = ref(true);
const isWindow = computed(() => form.value.schedule.mode === 'window');

const toggleDay = day => {
  const days = form.value.schedule.days;
  const i = days.indexOf(day);
  if (i >= 0) days.splice(i, 1);
  else days.push(day);
};

const setMode = mode => {
  form.value.schedule.mode = mode;
};

const close = () => emit('close');

const submit = () => {
  const f = form.value;
  if (!f.name || !f.name.trim()) {
    useAlert(t('AGENT_POLICY.VALIDATION.NAME_REQUIRED'));
    return;
  }
  if (f.percent == null || f.percent < 0 || f.percent > 100) {
    useAlert(t('AGENT_POLICY.VALIDATION.PERCENT_REQUIRED'));
    return;
  }
  if ([f.min_deposit, f.max_deposit, f.cap].some(v => v != null && v < 0)) {
    useAlert(t('AGENT_POLICY.VALIDATION.NEGATIVE', { name: f.name }));
    return;
  }
  if (isWindow.value) {
    if (!f.schedule.start_hm || !f.schedule.end_hm || f.schedule.end_hm <= f.schedule.start_hm) {
      useAlert(t('AGENT_POLICY.VALIDATION.WINDOW', { name: f.name }));
      return;
    }
  } else {
    // an always-on bonus carries no window fields
    f.schedule.days = [];
  }
  emit('save', JSON.parse(JSON.stringify(f)));
};
</script>

<template>
  <Modal v-model:show="show" :on-close="close">
    <div class="flex flex-col w-full max-h-[80vh] overflow-y-auto text-slate-800 dark:text-slate-100">
      <woot-modal-header
        :header-title="props.bonus ? $t('AGENT_POLICY.BONUS.EDIT_TITLE') : $t('AGENT_POLICY.BONUS.ADD_TITLE')"
        :header-content="$t('AGENT_POLICY.BONUS.MODAL_DESC')"
      />
      <form class="flex flex-col gap-4 p-1 mt-2" @submit.prevent="submit">
        <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <label class="flex flex-col gap-1 text-sm">
            {{ $t('AGENT_POLICY.BONUS.NAME') }}
            <input v-model="form.name" type="text" class="ap-input" :placeholder="$t('AGENT_POLICY.BONUS.NAME_PLACEHOLDER')" />
          </label>
          <label class="flex flex-col gap-1 text-sm">
            {{ $t('AGENT_POLICY.BONUS.KIND') }}
            <select v-model="form.kind" class="ap-input">
              <option v-for="k in KINDS" :key="k" :value="k">{{ k }}</option>
            </select>
          </label>
        </div>

        <div class="grid grid-cols-2 gap-3 lg:grid-cols-4">
          <label class="flex flex-col gap-1 text-sm">
            {{ $t('AGENT_POLICY.BONUS.PERCENT') }}
            <input v-model.number="form.percent" type="number" min="0" max="100" step="0.01" class="ap-input" placeholder="20" />
          </label>
          <label class="flex flex-col gap-1 text-sm">
            {{ $t('AGENT_POLICY.BONUS.MIN_DEPOSIT') }}
            <input v-model.number="form.min_deposit" type="number" min="0" step="0.01" class="ap-input" placeholder="10" />
          </label>
          <label class="flex flex-col gap-1 text-sm">
            {{ $t('AGENT_POLICY.BONUS.MAX_DEPOSIT') }}
            <input v-model.number="form.max_deposit" type="number" min="0" step="0.01" class="ap-input" :placeholder="$t('AGENT_POLICY.NO_CAP')" />
          </label>
          <label class="flex flex-col gap-1 text-sm">
            {{ $t('AGENT_POLICY.BONUS.CAP') }}
            <input v-model.number="form.cap" type="number" min="0" step="0.01" class="ap-input" :placeholder="$t('AGENT_POLICY.NO_CAP')" />
          </label>
        </div>

        <!-- schedule -->
        <div class="flex flex-col gap-2">
          <span class="text-sm font-medium">{{ $t('AGENT_POLICY.BONUS.SCHEDULE.TITLE') }}</span>
          <div class="inline-flex p-1 rounded-lg w-fit bg-slate-100 dark:bg-slate-800">
            <button
              type="button"
              class="px-3 py-1 text-sm rounded-md transition-colors"
              :class="!isWindow ? 'bg-white dark:bg-slate-700 shadow-sm font-medium' : 'text-slate-500'"
              @click="setMode('always')"
            >
              {{ $t('AGENT_POLICY.BONUS.SCHEDULE.ALWAYS') }}
            </button>
            <button
              type="button"
              class="px-3 py-1 text-sm rounded-md transition-colors"
              :class="isWindow ? 'bg-white dark:bg-slate-700 shadow-sm font-medium' : 'text-slate-500'"
              @click="setMode('window')"
            >
              {{ $t('AGENT_POLICY.BONUS.SCHEDULE.WINDOW') }}
            </button>
          </div>

          <div v-if="isWindow" class="flex flex-col gap-3 p-3 rounded-lg bg-slate-50 dark:bg-slate-800/40">
            <div class="flex flex-wrap gap-1.5">
              <button
                v-for="d in DAYS"
                :key="d.v"
                type="button"
                class="w-9 h-9 text-xs font-semibold rounded-full transition-colors"
                :class="form.schedule.days.includes(d.v)
                  ? 'bg-woot-500 text-white'
                  : 'bg-slate-200 dark:bg-slate-700 text-slate-600 dark:text-slate-300'"
                @click="toggleDay(d.v)"
              >
                {{ d.label }}
              </button>
            </div>
            <p class="text-xs text-slate-400">{{ $t('AGENT_POLICY.BONUS.SCHEDULE.EVERY_DAY_HINT') }}</p>
            <div class="grid grid-cols-2 gap-3 max-w-xs">
              <label class="flex flex-col gap-1 text-sm">
                {{ $t('AGENT_POLICY.BONUS.SCHEDULE.START') }}
                <input v-model="form.schedule.start_hm" type="time" class="ap-input" />
              </label>
              <label class="flex flex-col gap-1 text-sm">
                {{ $t('AGENT_POLICY.BONUS.SCHEDULE.END') }}
                <input v-model="form.schedule.end_hm" type="time" class="ap-input" />
              </label>
            </div>
          </div>
        </div>

        <label class="flex items-center gap-2 text-sm cursor-pointer">
          <input v-model="form.active" type="checkbox" class="w-4 h-4" />
          {{ $t('AGENT_POLICY.BONUS.ACTIVE') }}
        </label>

        <div class="flex justify-end gap-2 pt-2">
          <Button variant="ghost" @click.prevent="close">{{ $t('AGENT_POLICY.CANCEL') }}</Button>
          <Button type="submit">{{ $t('AGENT_POLICY.BONUS.SAVE') }}</Button>
        </div>
      </form>
    </div>
  </Modal>
</template>

<style scoped lang="scss">
.ap-input {
  @apply w-full px-3 py-2 text-sm rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-slate-800 dark:text-slate-100 outline-none transition-colors;

  &:focus {
    @apply border-woot-500 dark:border-woot-400;
  }
}
</style>
