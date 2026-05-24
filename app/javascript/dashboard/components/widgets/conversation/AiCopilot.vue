<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import PatraAiAPI from 'dashboard/api/patraAi';

const props = defineProps({
  conversationId: { type: Number, required: true },
  draft: { type: String, default: '' },
});

const emit = defineEmits(['use', 'edit']);

const { t } = useI18n();
const suggestion = ref('');
const loading = ref(false);
let debounceTimer = null;

const fetchSuggestion = async () => {
  if (!props.draft || props.draft.length < 3) {
    suggestion.value = '';
    return;
  }
  loading.value = true;
  try {
    const { data } = await PatraAiAPI.copilotSuggestion(props.conversationId, props.draft);
    suggestion.value = data.suggestion;
  } finally {
    loading.value = false;
  }
};

watch(
  () => props.draft,
  () => {
    clearTimeout(debounceTimer);
    debounceTimer = setTimeout(fetchSuggestion, 800);
  }
);

const useSuggestion = () => emit('use', suggestion.value);
const editSuggestion = () => emit('edit', suggestion.value);
const dismiss = () => { suggestion.value = ''; };
</script>

<template>
  <div
    v-if="suggestion"
    class="p-3 mt-2 text-sm rounded-lg border border-n-weak bg-n-alpha-1"
  >
    <p class="mb-2 text-n-slate-11">🤖 {{ $t('PATRA.AI.SUGGESTED') }}:</p>
    <p class="text-n-slate-12">{{ suggestion }}</p>
    <div class="flex gap-2 mt-2">
      <button class="px-2 py-1 text-xs rounded-lg bg-n-brand text-white" @click="useSuggestion">
        {{ $t('PATRA.AI.USE') }}
      </button>
      <button class="px-2 py-1 text-xs rounded-lg border border-n-weak" @click="editSuggestion">
        {{ $t('PATRA.AI.EDIT') }}
      </button>
      <button class="px-2 py-1 text-xs text-n-slate-11" @click="dismiss">
        {{ $t('PATRA.AI.DISMISS') }}
      </button>
    </div>
  </div>
</template>
