<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';

const { t } = useI18n();
const isEnabled = ref(false);

const { currentAccount, updateAccount } = useAccount();

watch(
  currentAccount,
  () => {
    const { audio_transcriptions } = currentAccount.value?.settings || {};
    isEnabled.value = !!audio_transcriptions;
  },
  { deep: true, immediate: true }
);

const updateAccountSettings = async settings => {
  try {
    await updateAccount(settings);
    useAlert(t('GENERAL_SETTINGS.FORM.AUDIO_TRANSCRIPTION.API.SUCCESS'));
  } catch (error) {
    useAlert(t('GENERAL_SETTINGS.FORM.AUDIO_TRANSCRIPTION.API.ERROR'));
  }
};

const toggleAudioTranscription = () => {
  updateAccountSettings({
    audio_transcriptions: isEnabled.value,
  });
};

const onSwitchClick = () => {
  isEnabled.value = !isEnabled.value;
  toggleAudioTranscription();
};
</script>

<template>
  <div class="card">
    <div class="tog-row">
      <div class="tr-l">
        <div class="tt">
          {{ t('GENERAL_SETTINGS.FORM.AUDIO_TRANSCRIPTION.TITLE') }}
        </div>
        <div class="ts">
          {{ t('GENERAL_SETTINGS.FORM.AUDIO_TRANSCRIPTION.NOTE') }}
        </div>
      </div>
      <div
        class="sw"
        :class="{ off: !isEnabled }"
        role="switch"
        :aria-checked="isEnabled"
        tabindex="0"
        @click="onSwitchClick"
        @keydown.enter.space.prevent="onSwitchClick"
      >
        <i />
      </div>
    </div>
  </div>
</template>

<style scoped>
.card {
  background: var(--surface, #0c0b12);
  border: 1px solid var(--border, #171520);
  border-radius: 16px;
  padding: 22px;
  margin-bottom: 16px;
}

.tog-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0;
}

.tog-row .tr-l .tt {
  font-size: 13.5px;
  font-weight: 500;
  color: var(--text, #ededf2);
}

.tog-row .tr-l .ts {
  font-size: 11.5px;
  color: var(--text-3, #75727f);
  margin-top: 2px;
}

.sw {
  width: 38px;
  height: 22px;
  border-radius: 12px;
  background: linear-gradient(
    135deg,
    var(--patra, #6e56cf),
    var(--patra-2, #8b5cf6)
  );
  position: relative;
  cursor: pointer;
  flex-shrink: 0;
  box-shadow: 0 0 12px var(--patra-glow, rgba(110, 86, 207, 0.55));
  transition: all 0.3s;
}

.sw i {
  position: absolute;
  top: 2px;
  right: 2px;
  width: 18px;
  height: 18px;
  border-radius: 50%;
  background: #fff;
  transition: all 0.3s;
}

.sw.off {
  background: var(--surface-4, #252233);
  box-shadow: none;
}

.sw.off i {
  right: auto;
  left: 2px;
}
</style>
