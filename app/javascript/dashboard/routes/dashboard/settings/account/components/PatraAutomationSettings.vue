<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import PatraSettingsAPI from 'dashboard/api/patraSettings';
import NextButton from 'dashboard/components-next/button/Button.vue';
import NextInput from 'next/input/Input.vue';

const { t } = useI18n();

const loading = ref(true);
const saving = ref(false);
const startTime = ref('09:00');
const endTime = ref('17:00');
const timezone = ref('America/New_York');
const reengageDays = ref(7);
const workingDays = ref(['monday', 'tuesday', 'wednesday', 'thursday', 'friday']);

const dayOptions = computed(() => [
  { id: 'monday', label: t('PATRA.SETTINGS.DAYS.MON') },
  { id: 'tuesday', label: t('PATRA.SETTINGS.DAYS.TUE') },
  { id: 'wednesday', label: t('PATRA.SETTINGS.DAYS.WED') },
  { id: 'thursday', label: t('PATRA.SETTINGS.DAYS.THU') },
  { id: 'friday', label: t('PATRA.SETTINGS.DAYS.FRI') },
  { id: 'saturday', label: t('PATRA.SETTINGS.DAYS.SAT') },
  { id: 'sunday', label: t('PATRA.SETTINGS.DAYS.SUN') },
]);

function toggleDay(dayId) {
  if (workingDays.value.includes(dayId)) {
    workingDays.value = workingDays.value.filter(d => d !== dayId);
  } else {
    workingDays.value = [...workingDays.value, dayId];
  }
}

onMounted(async () => {
  try {
    const { data } = await PatraSettingsAPI.get();
    const hours = data.business_hours || {};
    startTime.value = hours.start || '09:00';
    endTime.value = hours.end || '17:00';
    timezone.value = hours.timezone || 'America/New_York';
    workingDays.value = hours.days || workingDays.value;
    reengageDays.value = data.reengage_days || 7;
  } catch {
    // defaults
  } finally {
    loading.value = false;
  }
});

async function saveSettings() {
  saving.value = true;
  try {
    const { data } = await PatraSettingsAPI.update({
      reengage_days: Number(reengageDays.value) || 7,
      business_hours: {
        start: startTime.value,
        end: endTime.value,
        timezone: timezone.value,
        days: workingDays.value,
      },
    });
    reengageDays.value = data.reengage_days ?? reengageDays.value;
    if (data.business_hours) {
      startTime.value = data.business_hours.start || startTime.value;
      endTime.value = data.business_hours.end || endTime.value;
      timezone.value = data.business_hours.timezone || timezone.value;
      workingDays.value = data.business_hours.days || workingDays.value;
    }
    useAlert(t('PATRA.SETTINGS.SAVED'));
  } catch {
    useAlert(t('PATRA.SETTINGS.SAVE_ERROR'));
  } finally {
    saving.value = false;
  }
}
</script>

<template>
  <div v-if="!loading" class="mt-6 space-y-6 border-t border-n-weak pt-6">
    <div>
      <h3 class="text-base font-medium text-n-slate-12">
        {{ $t('PATRA.SETTINGS.BUSINESS_HOURS_TITLE') }}
      </h3>
      <p class="mt-1 text-sm text-n-slate-11">
        {{ $t('PATRA.SETTINGS.BUSINESS_HOURS_NOTE') }}
      </p>
      <div class="mt-4 grid gap-4 sm:grid-cols-3">
        <div>
          <label class="mb-1 block text-xs font-medium text-n-slate-11">
            {{ $t('PATRA.SETTINGS.START') }}
          </label>
          <NextInput v-model="startTime" type="time" />
        </div>
        <div>
          <label class="mb-1 block text-xs font-medium text-n-slate-11">
            {{ $t('PATRA.SETTINGS.END') }}
          </label>
          <NextInput v-model="endTime" type="time" />
        </div>
        <div>
          <label class="mb-1 block text-xs font-medium text-n-slate-11">
            {{ $t('PATRA.SETTINGS.TIMEZONE') }}
          </label>
          <NextInput v-model="timezone" />
        </div>
      </div>
      <div class="mt-3 flex flex-wrap gap-2">
        <button
          v-for="day in dayOptions"
          :key="day.id"
          type="button"
          class="rounded-full px-3 py-1 text-xs font-medium border transition-colors"
          :class="
            workingDays.includes(day.id)
              ? 'border-n-brand bg-n-brand/10 text-n-brand'
              : 'border-n-weak text-n-slate-11'
          "
          @click="toggleDay(day.id)"
        >
          {{ day.label }}
        </button>
      </div>
    </div>

    <div>
      <h3 class="text-base font-medium text-n-slate-12">
        {{ $t('PATRA.SETTINGS.REENGAGE_TITLE') }}
      </h3>
      <p class="mt-1 text-sm text-n-slate-11">
        {{ $t('PATRA.SETTINGS.REENGAGE_NOTE') }}
      </p>
      <div class="mt-3 flex items-center gap-2">
        <NextInput v-model="reengageDays" type="number" class="!w-20" />
        <span class="text-sm text-n-slate-11">{{ $t('PATRA.SETTINGS.DAYS_LABEL') }}</span>
      </div>
    </div>

    <NextButton
      :label="$t('PATRA.SETTINGS.SAVE')"
      :is-loading="saving"
      @click="saveSettings"
    />
  </div>
</template>
