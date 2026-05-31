<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import PatraSettingsAPI from 'dashboard/api/patraSettings';
import NextInput from 'next/input/Input.vue';

const { t } = useI18n();

const loading = ref(true);
const saving = ref(false);
const startTime = ref('09:00');
const endTime = ref('17:00');
const timezone = ref('America/New_York');
const workingDays = ref([
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
]);

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
      business_hours: {
        start: startTime.value,
        end: endTime.value,
        timezone: timezone.value,
        days: workingDays.value,
      },
    });
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
  <div class="patra-hours">
    <div v-if="!loading" class="card">
      <div class="card-t display">
        <span class="dot" />
        {{ $t('PATRA.SETTINGS.BUSINESS_HOURS_TITLE') }}
      </div>
      <p class="persona-note">{{ $t('PATRA.SETTINGS.BUSINESS_HOURS_NOTE') }}</p>

      <div class="fld row">
        <div>
          <label>{{ $t('PATRA.SETTINGS.START') }}</label>
          <NextInput v-model="startTime" type="time" class="pat-input" />
        </div>
        <div>
          <label>{{ $t('PATRA.SETTINGS.END') }}</label>
          <NextInput v-model="endTime" type="time" class="pat-input" />
        </div>
        <div>
          <label>{{ $t('PATRA.SETTINGS.TIMEZONE') }}</label>
          <NextInput v-model="timezone" class="pat-input" />
        </div>
      </div>

      <div class="fld">
        <label>{{ $t('PATRA.SETTINGS.ACTIVE_DAYS') }}</label>
        <div class="days">
          <button
            v-for="day in dayOptions"
            :key="day.id"
            type="button"
            class="day"
            :class="{ on: workingDays.includes(day.id) }"
            @click="toggleDay(day.id)"
          >
            {{ day.label }}
          </button>
        </div>
      </div>

      <button
        type="button"
        class="btn primary"
        :disabled="saving"
        @click="saveSettings"
      >
        {{ saving ? $t('PATRA.SETTINGS.SAVING') : $t('PATRA.SETTINGS.SAVE') }}
      </button>
    </div>
  </div>
</template>

<style scoped>
.display {
  font-family: 'Space Grotesk', sans-serif;
}

.card {
  position: relative;
  isolation: isolate;
  background: var(--surface, #0c0b12);
  border: 1px solid var(--border, #171520);
  border-radius: 16px;
  padding: 22px;
  margin-bottom: 16px;
}

.card-t {
  font-weight: 600;
  font-size: 15px;
  display: flex;
  align-items: center;
  gap: 8px;
  margin-bottom: 18px;
}

.card-t .dot {
  width: 7px;
  height: 7px;
  border-radius: 50%;
  background: var(--patra-2, #8b5cf6);
  box-shadow: 0 0 8px var(--patra-glow, rgba(110, 86, 207, 0.55));
}

.persona-note {
  font-size: 12.5px;
  color: var(--text-3, #75727f);
  margin: -6px 0 14px;
}

.fld {
  margin-bottom: 16px;
}

.fld label {
  display: block;
  font-size: 12.5px;
  color: var(--text-2, #a8a6b6);
  margin-bottom: 6px;
  font-weight: 500;
}

.fld.row {
  display: grid;
  grid-template-columns: 1fr 1fr 1fr;
  gap: 12px;
}

.fld :deep(.pat-input input) {
  width: 100%;
  background: var(--canvas, #050409) !important;
  border: 1px solid var(--border, #171520) !important;
  border-radius: 10px !important;
  padding: 10px 13px !important;
  color: var(--text, #ededf2) !important;
  font-size: 13px !important;
  box-shadow: none !important;
}

.fld :deep(.pat-input input:focus) {
  border-color: var(--patra, #6e56cf) !important;
  box-shadow: 0 0 0 3px rgba(110, 86, 207, 0.11) !important;
}

.days {
  display: flex;
  gap: 7px;
  flex-wrap: wrap;
}

.day {
  padding: 7px 13px;
  border-radius: 9px;
  border: 1px solid var(--border, #171520);
  font-size: 12.5px;
  cursor: pointer;
  transition: all 0.2s cubic-bezier(0.34, 1.56, 0.64, 1);
  color: var(--text-3, #75727f);
  background: transparent;
}

.day:hover {
  border-color: var(--border-hi, #2e2940);
  transform: translateY(-2px);
}

.day.on {
  background: linear-gradient(
    135deg,
    var(--patra, #6e56cf),
    var(--patra-deep, #5b45b0)
  );
  color: #fff;
  border-color: transparent;
  box-shadow: 0 3px 10px var(--patra-glow, rgba(110, 86, 207, 0.55));
}

.btn {
  font-size: 13px;
  font-weight: 600;
  padding: 10px 18px;
  border-radius: 10px;
  border: 1px solid var(--border-hi, #2e2940);
  background: var(--surface-2, #131119);
  color: var(--text, #ededf2);
  cursor: pointer;
  transition: all 0.22s cubic-bezier(0.34, 1.56, 0.64, 1);
}

.btn:hover:not(:disabled) {
  transform: translateY(-2px);
  box-shadow: 0 6px 16px rgba(0, 0, 0, 0.3);
  border-color: var(--patra, #6e56cf);
}

.btn:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}

.btn.primary {
  background: linear-gradient(
    135deg,
    var(--patra, #6e56cf),
    var(--patra-deep, #5b45b0)
  );
  border-color: transparent;
  color: #fff;
  box-shadow: 0 4px 14px var(--patra-glow, rgba(110, 86, 207, 0.55));
}

.btn.primary:hover:not(:disabled) {
  filter: brightness(1.12);
}
</style>
