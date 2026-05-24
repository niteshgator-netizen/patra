<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { vOnClickOutside } from '@vueuse/components';
import { useAlert } from 'dashboard/composables';
import { messageTimestamp } from 'shared/helpers/timeHelper';
import ScheduledMessagesAPI from 'dashboard/api/scheduledMessages';
import NextButton from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  show: {
    type: Boolean,
    default: false,
  },
  conversationId: {
    type: Number,
    required: true,
  },
  message: {
    type: String,
    default: '',
  },
});

const emit = defineEmits(['close', 'scheduled']);

const { t } = useI18n();
const scheduledAt = ref('');
const isSubmitting = ref(false);

const minDateTime = computed(() => {
  const now = new Date();
  now.setMinutes(now.getMinutes() + 1);
  const pad = value => String(value).padStart(2, '0');
  return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}T${pad(now.getHours())}:${pad(now.getMinutes())}`;
});

const canSchedule = computed(
  () => !!scheduledAt.value && !isSubmitting.value && !!props.message.trim()
);

const resetForm = () => {
  scheduledAt.value = '';
};

const handleClose = () => {
  resetForm();
  emit('close');
};

const handleSchedule = async () => {
  if (!canSchedule.value) return;

  isSubmitting.value = true;
  try {
    await ScheduledMessagesAPI.create({
      conversation_id: props.conversationId,
      content: props.message.trim(),
      scheduled_at: new Date(scheduledAt.value).toISOString(),
    });

    const formattedTime = messageTimestamp(
      Math.floor(new Date(scheduledAt.value).getTime() / 1000),
      'LLL d, h:mm a'
    );
    useAlert(t('PATRA.SCHEDULED.SUCCESS', { time: formattedTime }));
    emit('scheduled');
    handleClose();
  } catch (error) {
    const errorMessage =
      error?.response?.data?.error || t('PATRA.SCHEDULED.ERROR');
    useAlert(errorMessage);
  } finally {
    isSubmitting.value = false;
  }
};
</script>

<template>
  <div
    v-if="show"
    v-on-click-outside="handleClose"
    class="absolute bottom-full right-0 z-50 mb-2 w-72 rounded-xl border border-n-weak bg-n-solid-3 p-4 shadow-xl"
  >
    <p class="mb-3 text-sm font-medium text-n-slate-12">
      {{ $t('PATRA.SCHEDULED.PICK_TIME') }}
    </p>
    <input
      v-model="scheduledAt"
      type="datetime-local"
      :min="minDateTime"
      class="mb-4 w-full rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
    />
    <div class="flex justify-end gap-2">
      <NextButton
        :label="$t('PATRA.SCHEDULED.CANCEL')"
        slate
        faded
        sm
        @click="handleClose"
      />
      <NextButton
        :label="$t('PATRA.SCHEDULED.CONFIRM')"
        sm
        color="blue"
        :disabled="!canSchedule"
        :is-loading="isSubmitting"
        @click="handleSchedule"
      />
    </div>
  </div>
</template>
