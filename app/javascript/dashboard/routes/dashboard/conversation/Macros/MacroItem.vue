<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore } from 'dashboard/composables/store';
import { CONVERSATION_EVENTS } from '../../../../helper/AnalyticsHelper/events';
import { useTrack } from 'dashboard/composables';

import MacroPreview from './MacroPreview.vue';

const props = defineProps({
  macro: {
    type: Object,
    required: true,
  },
  conversationId: {
    type: [Number, String],
    required: true,
  },
});

const store = useStore();
const { t } = useI18n();

const isExecuting = ref(false);
const showPreview = ref(false);

const executeMacro = async macro => {
  try {
    isExecuting.value = true;
    await store.dispatch('macros/execute', {
      macroId: macro.id,
      conversationIds: [props.conversationId],
    });
    useTrack(CONVERSATION_EVENTS.EXECUTED_A_MACRO);
    useAlert(t('MACROS.EXECUTE.EXECUTED_SUCCESSFULLY'));
  } catch (error) {
    useAlert(t('MACROS.ERROR'));
  } finally {
    isExecuting.value = false;
  }
};

const toggleMacroPreview = () => {
  showPreview.value = !showPreview.value;
};

const closeMacroPreview = () => {
  showPreview.value = false;
};
</script>

<template>
  <div class="macro-row relative drag-handle">
    <span class="min-w-0 truncate">{{ macro.name }}</span>
    <div class="flex items-center gap-1 shrink-0">
      <button
        type="button"
        class="run"
        :disabled="isExecuting"
        @click="executeMacro(macro)"
      >
        {{ isExecuting ? '…' : $t('MACROS.EXECUTE.BUTTON_TOOLTIP') }}
      </button>
      <button
        type="button"
        class="vc-copy"
        :aria-label="$t('MACROS.EXECUTE.PREVIEW')"
        @click="toggleMacroPreview"
      />
    </div>
    <transition name="menu-slide">
      <MacroPreview
        v-if="showPreview"
        v-on-clickaway="closeMacroPreview"
        :macro="macro"
      />
    </transition>
  </div>
</template>
