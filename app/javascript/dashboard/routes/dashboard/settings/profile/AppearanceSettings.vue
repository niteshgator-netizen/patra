<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  setAppearance,
  getSelectedColorScheme,
} from 'dashboard/helper/themeHelper';
import { LocalStorage } from 'shared/helpers/localStorage';

const { t } = useI18n();

const selected = ref(getSelectedColorScheme());
const brightness = ref(Number(LocalStorage.get('patra_brightness')) || 0);

const options = [
  { key: 'light', icon: 'i-lucide-sun' },
  { key: 'dark', icon: 'i-lucide-moon' },
  { key: 'auto', icon: 'i-lucide-monitor' },
];

const pick = key => {
  selected.value = key;
  setAppearance(key);
};

const onBrightness = value => {
  brightness.value = Number(value) || 0;
  LocalStorage.set('patra_brightness', brightness.value);
  // App.vue owns the #patra-dimmer overlay; tell it the value changed.
  window.dispatchEvent(
    new CustomEvent('patra:brightness', { detail: brightness.value })
  );
};
</script>

<template>
  <div class="flex flex-col gap-5 w-full">
    <div>
      <label class="block text-sm font-medium text-n-slate-12 mb-1">
        {{ t('PROFILE_SETTINGS.FORM.INTERFACE_SECTION.APPEARANCE.TITLE') }}
      </label>
      <p class="text-sm text-n-slate-11 mb-3">
        {{ t('PROFILE_SETTINGS.FORM.INTERFACE_SECTION.APPEARANCE.NOTE') }}
      </p>
      <div class="flex gap-3">
        <button
          v-for="option in options"
          :key="option.key"
          type="button"
          class="flex items-center gap-2 px-4 py-2 rounded-xl outline outline-1 text-sm font-medium transition-colors"
          :class="
            selected === option.key
              ? 'outline-n-brand/60 bg-n-brand/10 text-n-slate-12'
              : 'outline-n-weak text-n-slate-11 hover:bg-n-alpha-1'
          "
          @click="pick(option.key)"
        >
          <span :class="option.icon" class="size-4" />
          {{
            t(
              `PROFILE_SETTINGS.FORM.INTERFACE_SECTION.APPEARANCE.OPTIONS.${option.key.toUpperCase()}`
            )
          }}
        </button>
      </div>
    </div>
    <div>
      <label class="block text-sm font-medium text-n-slate-12 mb-1">
        {{
          t('PROFILE_SETTINGS.FORM.INTERFACE_SECTION.APPEARANCE.DIMMER.TITLE')
        }}
      </label>
      <p class="text-sm text-n-slate-11 mb-3">
        {{
          t('PROFILE_SETTINGS.FORM.INTERFACE_SECTION.APPEARANCE.DIMMER.NOTE')
        }}
      </p>
      <input
        type="range"
        min="0"
        max="80"
        :value="brightness"
        class="w-56 accent-n-brand"
        @input="onBrightness($event.target.value)"
      />
    </div>
  </div>
</template>
