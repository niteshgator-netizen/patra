<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useElementSize } from '@vueuse/core';
import BackButton from '../BackButton.vue';
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
import PatraConversationsAPI from 'dashboard/api/patraConversations';
import types from 'dashboard/store/mutation-types';

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

// Patra: channel emoji for the inbox row (label is always inbox.name to avoid duplicating channel vs inbox).
const CHANNEL_ICONS = {
  'Channel::FacebookPage': '💬',
  'Channel::Instagram': '📸',
  'Channel::Whatsapp': '💬',
  'Channel::Telegram': '✈️',
};
const channelIcon = computed(
  () => CHANNEL_ICONS[inbox.value?.channel_type] || '💬'
);
const inboxDisplayName = computed(() => inbox.value?.name || 'Chat');

// Patra: contact presence ("Active now" / "Active Xm ago") for the
// sub-row under the contact name. Backend service formats the text and
// returns last_active=null for entries older than 24h, which hides it.
const contactPresence = ref({ online: false, last_active: null });
let presencePollTimer = null;

const fetchContactPresence = async () => {
  const contactId = props.chat?.meta?.sender?.id;
  if (!contactId) return;
  try {
    const { data } = await ContactAPI.getPresence(contactId);
    contactPresence.value = {
      online: Boolean(data.online),
      last_active: data.last_active || null,
    };
  } catch {
    contactPresence.value = { online: false, last_active: null };
  }
};

const startPresencePolling = () => {
  if (presencePollTimer) clearInterval(presencePollTimer);
  fetchContactPresence();
  presencePollTimer = setInterval(fetchContactPresence, 30_000);
};

onMounted(() => {
  startPresencePolling();
});

onBeforeUnmount(() => {
  if (presencePollTimer) clearInterval(presencePollTimer);
});

watch(
  () => [props.chat?.id, props.chat?.meta?.sender?.id],
  () => {
    contactPresence.value = { online: false, last_active: null };
    startPresencePolling();
  }
);

const avatarPresenceStatus = computed(() => {
  if (contactPresence.value.online) return 'online';
  return currentContact.value?.availability_status || null;
});

const isPinned = computed(
  () => currentChat.value?.additional_attributes?.pinned === true
);

const summaryText = ref('');
const summaryLoading = ref(false);
const showSummary = ref(false);

const togglePin = async () => {
  const id = props.chat?.id;
  if (!id) return;
  try {
    const { data } = await PatraConversationsAPI.togglePin(id);
    const chat = { ...currentChat.value };
    store.commit(types.UPDATE_CONVERSATION, {
      ...chat,
      id: chat.id || id,
      updated_at: data.updated_at || chat.updated_at,
      additional_attributes: {
        ...(chat.additional_attributes || {}),
        pinned: data.pinned,
      },
    });
  } catch {
    useAlert(t('PATRA.CONVERSATION.PIN_ERROR'));
  }
};

const fetchSummary = async () => {
  const id = props.chat?.id;
  if (!id || summaryLoading.value) return;
  showSummary.value = true;
  summaryLoading.value = true;
  summaryText.value = '';
  try {
    const { data } = await PatraConversationsAPI.getSummary(id);
    summaryText.value = data.summary || t('PATRA.CONVERSATION.SUMMARY_ERROR');
  } catch {
    summaryText.value = t('PATRA.CONVERSATION.SUMMARY_ERROR');
  } finally {
    summaryLoading.value = false;
  }
};
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
            class="text-base font-semibold truncate leading-tight text-n-slate-12"
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
          v-if="contactPresence.last_active"
          class="text-xs leading-tight"
          :class="
            contactPresence.online
              ? 'text-[var(--patra-green)]'
              : 'text-n-slate-11'
          "
        >
          {{ contactPresence.last_active }}
        </div>
        <!-- Patra: inbox + conversation id (one line; inbox name once, id de-emphasized) -->
        <div
          class="flex items-center gap-1 overflow-hidden text-xs conversation--header--actions text-n-slate-11 text-ellipsis whitespace-nowrap max-w-full"
        >
          <span class="truncate shrink min-w-0">
            {{ channelIcon }} {{ inboxDisplayName }}
          </span>
          <span class="text-n-slate-10 shrink-0" aria-hidden="true">•</span>
          <button
            type="button"
            class="shrink-0 text-[11px] font-normal leading-none text-n-slate-10 hover:text-n-slate-11 !p-0 cursor-pointer tabular-nums"
            @click="copyConversationId"
          >
            #{{ chat.id }}
          </button>
          <template v-if="isSnoozed">
            <span class="text-n-slate-10 shrink-0" aria-hidden="true">•</span>
            <span class="truncate font-medium text-n-amber-10 shrink min-w-0">
              {{ snoozedDisplayText }}
            </span>
          </template>
        </div>
      </div>
    </div>
    <div
      class="flex flex-row items-center justify-start xl:justify-end flex-shrink-0 gap-2 w-full xl:w-auto header-actions-wrap relative overflow-visible"
    >
      <SLACardLabel
        v-if="hasSlaPolicyId"
        :chat="chat"
        show-extended-info
        :parent-width="width"
        class="hidden md:flex"
      />
      <!-- Patra: pin + summary -->
      <button
        type="button"
        class="inline-flex items-center gap-1 px-2 py-1 rounded-full text-xs font-medium border whitespace-nowrap border-n-weak text-n-slate-11 hover:bg-n-alpha-2"
        :class="isPinned ? 'bg-n-amber-9/15 text-n-amber-11 border-n-amber-9/30' : ''"
        :title="isPinned ? $t('PATRA.CONVERSATION.UNPIN') : $t('PATRA.CONVERSATION.PIN')"
        @click="togglePin"
      >
        📌
      </button>
      <button
        type="button"
        class="inline-flex items-center gap-1 px-2 py-1 rounded-full text-xs font-medium border whitespace-nowrap border-n-weak text-n-slate-11 hover:bg-n-alpha-2 disabled:opacity-60"
        :disabled="summaryLoading"
        @click="fetchSummary"
      >
        <span v-if="summaryLoading" class="inline-block size-3 animate-spin rounded-full border-2 border-n-slate-8 border-t-n-brand" />
        📋 {{ $t('PATRA.CONVERSATION.SUMMARY') }}
      </button>
      <div
        v-if="showSummary"
        class="absolute top-full right-0 z-30 mt-1 w-72 max-w-sm rounded-lg border border-n-weak bg-n-solid-1 p-3 text-xs text-n-slate-12 shadow-lg"
      >
        <p v-if="summaryLoading" class="m-0 text-n-slate-11">
          {{ $t('PATRA.CONVERSATION.SUMMARY_LOADING') }}
        </p>
        <p v-else class="m-0 whitespace-pre-wrap">{{ summaryText }}</p>
        <button
          type="button"
          class="mt-2 text-n-brand hover:underline"
          @click="showSummary = false"
        >
          {{ $t('PATRA.CONVERSATION.CLOSE') }}
        </button>
      </div>
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
