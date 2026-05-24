<script setup>
import { useStore } from 'vuex';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';

const REACTIONS = ['👍', '❤️', '😂'];

const props = defineProps({
  conversationId: {
    type: Number,
    required: true,
  },
});

const store = useStore();
const { t } = useI18n();
const currentUser = useMapGetter('getCurrentUser');

const sendReaction = async emoji => {
  try {
    await store.dispatch('createPendingMessageAndSend', {
      conversationId: props.conversationId,
      message: emoji,
      private: false,
      sender: {
        name: currentUser.value.name,
        thumbnail: currentUser.value.avatar_url,
      },
    });
  } catch (error) {
    const errorMessage =
      error?.response?.data?.error || t('CONVERSATION.MESSAGE_ERROR');
    useAlert(errorMessage);
  }
};
</script>

<template>
  <div
    class="absolute -top-3 z-20 flex items-center gap-0.5 rounded-full border border-n-weak bg-n-solid-3 px-1 py-0.5 opacity-0 shadow-md transition-opacity group-hover/message:opacity-100 ltr:right-0 rtl:left-0"
  >
    <button
      v-for="emoji in REACTIONS"
      :key="emoji"
      type="button"
      class="flex size-7 items-center justify-center rounded-full text-base hover:bg-n-slate-3"
      @click.stop="sendReaction(emoji)"
    >
      {{ emoji }}
    </button>
  </div>
</template>
