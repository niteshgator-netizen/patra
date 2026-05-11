<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useElementSize } from '@vueuse/core';
import BackButton from '../BackButton.vue';
import InboxName from '../InboxName.vue';
import MoreActions from './MoreActions.vue';
import Avatar from 'next/avatar/Avatar.vue';
import SLACardLabel from './components/SLACardLabel.vue';
import wootConstants from 'dashboard/constants/globals';
import { conversationListPageURL } from 'dashboard/helper/URLHelper';
import { snoozedReopenTime } from 'dashboard/helper/snoozeHelpers';
import { useInbox } from 'dashboard/composables/useInbox';
import { useI18n } from 'vue-i18n';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import { useAlert } from 'dashboard/composables';
import { emitter } from 'shared/helpers/mitt';
import ContactAPI from 'dashboard/api/contacts';

const props = defineProps({
  chat: {
    type: Object,
    default: () => ({}),
  },
  showBackButton: {
    type: Boolean,
    default: false,
  },
});

const { t } = useI18n();
const store = useStore();
const route = useRoute();
const conversationHeader = ref(null);
const { width } = useElementSize(conversationHeader);
const { isAWebWidgetInbox } = useInbox();

const currentChat = computed(() => store.getters.getSelectedChat);
const accountId = computed(() => store.getters.getCurrentAccountId);

const chatMetadata = computed(() => props.chat.meta);

const backButtonUrl = computed(() => {
  const {
    params: { inbox_id: inboxId, label, teamId, id: customViewId },
    name,
  } = route;

  const conversationTypeMap = {
    conversation_through_mentions: 'mention',
    conversation_through_participating: 'participating',
    conversation_through_unattended: 'unattended',
  };
  return conversationListPageURL({
    accountId: accountId.value,
    inboxId,
    label,
    teamId,
    conversationType: conversationTypeMap[name],
    customViewId,
  });
});

const isHMACVerified = computed(() => {
  if (!isAWebWidgetInbox.value) {
    return true;
  }
  return chatMetadata.value.hmac_verified;
});

const currentContact = computed(() =>
  store.getters['contacts/getContact'](props.chat.meta.sender.id)
);

const isSnoozed = computed(
  () => currentChat.value.status === wootConstants.STATUS_TYPE.SNOOZED
);

const snoozedDisplayText = computed(() => {
  const { snoozed_until: snoozedUntil } = currentChat.value;
  if (snoozedUntil) {
    return `${t('CONVERSATION.HEADER.SNOOZED_UNTIL')} ${snoozedReopenTime(snoozedUntil)}`;
  }
  return t('CONVERSATION.HEADER.SNOOZED_UNTIL_NEXT_REPLY');
});

const inbox = computed(() => {
  const { inbox_id: inboxId } = props.chat;
  return store.getters['inboxes/getInbox'](inboxId);
});

const hasMultipleInboxes = computed(
  () => store.getters['inboxes/getInboxes'].length > 1
);

const hasSlaPolicyId = computed(() => props.chat?.sla_policy_id);

const copyConversationId = async () => {
  try {
    await copyTextToClipboard(String(props.chat.id));
    useAlert(t('CONVERSATION.HEADER.COPY_ID_SUCCESS'));
  } catch (error) {
    // error
  }
};

// Patra: AI toggle / take-over. `ai-off` is the opt-out label the Ai::ReplyJob
// reads server-side; toggling it here is enough to pause or resume auto-reply.
const aiOff = computed(() =>
  (currentChat.value?.labels || []).includes('ai-off')
);

const updateAiLabel = async action => {
  const id = currentChat.value?.id;
  if (!id) return;
  await store.dispatch('bulkActions/process', {
    type: 'Conversation',
    ids: [id],
    labels: { [action]: ['ai-off'] },
  });
};

const toggleAiOff = () => updateAiLabel(aiOff.value ? 'remove' : 'add');

const takeOver = async () => {
  if (!aiOff.value) await updateAiLabel('add');
  // ReplyBox listens for this and focuses its editor — see ReplyBox.vue.
  emitter.emit('patra:focus-reply');
};

// Patra: channel emoji + display name for the sub-row under the contact name.
const CHANNEL_LABELS = {
  'Channel::FacebookPage': { icon: '📘', name: 'Facebook' },
  'Channel::Instagram': { icon: '📸', name: 'Instagram' },
  'Channel::Whatsapp': { icon: '💬', name: 'WhatsApp' },
  'Channel::Telegram': { icon: '✈️', name: 'Telegram' },
};
const channelMeta = computed(() => {
  const fallback = { icon: '💬', name: inbox.value?.name || 'Chat' };
  return CHANNEL_LABELS[inbox.value?.channel_type] || fallback;
});
const channelIcon = computed(() => channelMeta.value.icon);
const channelName = computed(() => channelMeta.value.name);

const supportsFacebookPresence = computed(() => {
  const ch = inbox.value?.channel_type;
  if (ch === 'Channel::FacebookPage') return true;
  if (ch === 'Channel::Api' && inbox.value?.additional_attributes?.fb_page_id) {
    return true;
  }
  return false;
});

const fbPresence = ref({ online: false, last_active: null });
let fbPresencePollTimer = null;

const fetchFacebookPresence = async () => {
  if (!supportsFacebookPresence.value) return;
  const contactId = props.chat?.meta?.sender?.id;
  if (!contactId) return;
  try {
    const { data } = await ContactAPI.getPresence(contactId);
    fbPresence.value = {
      online: Boolean(data.online),
      last_active: data.last_active || null,
    };
  } catch {
    fbPresence.value = { online: false, last_active: null };
  }
};

const startFacebookPresencePolling = () => {
  if (fbPresencePollTimer) clearInterval(fbPresencePollTimer);
  if (!supportsFacebookPresence.value) return;
  fetchFacebookPresence();
  fbPresencePollTimer = setInterval(fetchFacebookPresence, 30_000);
};

onMounted(() => {
  startFacebookPresencePolling();
});

onBeforeUnmount(() => {
  if (fbPresencePollTimer) clearInterval(fbPresencePollTimer);
});

watch(
  () => [props.chat?.id, props.chat?.meta?.sender?.id, inbox.value?.id],
  () => {
    fbPresence.value = { online: false, last_active: null };
    startFacebookPresencePolling();
  }
);

const avatarPresenceStatus = computed(() => {
  if (!supportsFacebookPresence.value) {
    return currentContact.value?.availability_status || null;
  }
  return fbPresence.value.online ? 'online' : null;
});
</script>

<template>
  <div
    ref="conversationHeader"
    class="flex flex-col gap-3 items-center justify-between flex-1 w-full min-w-0 xl:flex-row px-3 pt-3 pb-2 h-24 xl:h-12"
  >
    <div
      class="flex items-center justify-start w-full xl:w-auto max-w-full min-w-0 xl:flex-1"
    >
      <BackButton
        v-if="showBackButton"
        :back-url="backButtonUrl"
        class="ltr:mr-2 rtl:ml-2"
      />
      <Avatar
        :name="currentContact.name"
        :src="currentContact.thumbnail"
        :size="32"
        :status="avatarPresenceStatus"
        hide-offline-status
        rounded-full
      />
      <div
        class="flex flex-col items-start min-w-0 ml-2 overflow-hidden rtl:ml-0 rtl:mr-2"
      >
        <div class="flex flex-row items-center max-w-full gap-1 p-0 m-0">
          <span
            class="text-sm font-medium truncate leading-tight text-n-slate-12"
          >
            {{ currentContact.name }}
          </span>
          <fluent-icon
            v-if="!isHMACVerified"
            v-tooltip="$t('CONVERSATION.UNVERIFIED_SESSION')"
            size="14"
            class="text-n-amber-10 my-0 mx-0 min-w-[14px] flex-shrink-0"
            icon="warning"
          />
        </div>
        <!-- Patra: active status (under contact name) -->
        <div
          v-if="fbPresence.last_active"
          class="text-xs leading-tight"
          :class="
            fbPresence.online
              ? 'text-[var(--patra-green)]'
              : 'text-n-slate-11'
          "
        >
          {{ fbPresence.last_active }}
        </div>
        <!-- Patra: channel sub-row -->
        <div
          class="chat-sub flex items-center gap-1 text-xs text-n-slate-11"
        >
          <span>{{ channelIcon }} {{ channelName }}</span>
        </div>

        <div
          class="flex items-center gap-1 overflow-hidden text-xs conversation--header--actions text-n-slate-11 text-ellipsis whitespace-nowrap"
        >
          <button
            type="button"
            class="truncate text-label-small text-n-slate-11 hover:text-n-slate-12 !p-0 cucursor-pointer"
            @click="copyConversationId"
          >
            {{ `#${chat.id}` }}
          </button>
          <span v-if="hasMultipleInboxes">•</span>
          <InboxName v-if="hasMultipleInboxes" :inbox="inbox" class="!mx-0" />
          <span v-if="isSnoozed">•</span>
          <span v-if="isSnoozed" class="font-medium text-n-amber-10">
            {{ snoozedDisplayText }}
          </span>
        </div>
      </div>
    </div>
    <div
      class="flex flex-row items-center justify-start xl:justify-end flex-shrink-0 gap-2 w-full xl:w-auto header-actions-wrap"
    >
      <SLACardLabel
        v-if="hasSlaPolicyId"
        :chat="chat"
        show-extended-info
        :parent-width="width"
        class="hidden md:flex"
      />
      <!-- Patra: AI status / pause toggle -->
      <button
        type="button"
        class="inline-flex items-center gap-1 px-3 py-1 rounded-full text-xs font-medium border whitespace-nowrap"
        :class="
          aiOff
            ? 'bg-[var(--patra-red-soft)] text-[var(--patra-red)] border-[var(--patra-red)]'
            : 'bg-[var(--patra-green-soft)] text-[var(--patra-green)] border-[var(--patra-green)]'
        "
        @click="toggleAiOff"
      >
        {{ aiOff ? '👤 Human — AI Paused' : '🤖 Bella — AI Active' }}
      </button>
      <!-- Patra: human take-over (adds ai-off + focuses reply editor) -->
      <button
        v-if="!aiOff"
        type="button"
        class="inline-flex items-center gap-1 px-3 py-1 rounded-full text-xs font-medium border whitespace-nowrap bg-[var(--patra-amber-soft)] text-[var(--patra-amber)] border-[var(--patra-amber)]"
        @click="takeOver"
      >
        Take over
      </button>
      <MoreActions :conversation-id="currentChat.id" />
    </div>
  </div>
</template>
