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
import ConversationMessageSearch from './ConversationMessageSearch.vue';
import ConversationInfoPanel from './ConversationInfoPanel.vue';

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
    conversation_through_resolved: 'resolved',
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

const isPinned = computed(() => {
  const pinned =
    props.chat?.additional_attributes?.pinned ??
    currentChat.value?.additional_attributes?.pinned;
  return pinned === true || pinned === 'true';
});

const showMessageSearch = ref(false);
const showInfoPanel = ref(false);

const togglePin = async () => {
  const id = Number(props.chat?.id);
  if (!id) return;
  try {
    const { data } = await PatraConversationsAPI.togglePin(id);
    const chat = currentChat.value?.id
      ? { ...currentChat.value }
      : { ...props.chat };
    const now = Math.floor(Date.now() / 1000);
    store.commit(types.UPDATE_CONVERSATION, {
      ...chat,
      id,
      updated_at: Math.max(
        Number(data.updated_at) || 0,
        Number(chat.updated_at) || 0,
        now
      ),
      additional_attributes: {
        ...(chat.additional_attributes || {}),
        pinned: Boolean(data.pinned),
      },
    });
  } catch {
    useAlert(t('PATRA.CONVERSATION.PIN_ERROR'));
  }
};

const aiToggleLabel = computed(() =>
  aiOff.value
    ? t('PATRA.CONVERSATION.AI_PAUSED')
    : t('PATRA.CONVERSATION.AI_ACTIVE')
);

const pinButtonLabel = computed(() =>
  isPinned.value
    ? t('PATRA.CONVERSATION.UNPIN_SHORT')
    : t('PATRA.CONVERSATION.PIN_SHORT')
);
</script>

<template>
  <div ref="conversationHeader" class="patra-conv-head">
    <div class="patra-conv-head-l">
      <BackButton
        v-if="showBackButton"
        :back-url="backButtonUrl"
        class="patra-conv-head-back ltr:mr-1 rtl:ml-1"
      />
      <Avatar
        :name="currentContact.name"
        :src="currentContact.thumbnail"
        :size="42"
        :status="avatarPresenceStatus"
        hide-offline-status
        rounded-full
        class="patra-conv-head-avatar"
      />
      <div class="patra-conv-head-info min-w-0">
        <div class="patra-conv-head-name">
          <span class="patra-conv-head-name-text truncate">
            {{ currentContact.name }}
          </span>
          <fluent-icon
            v-if="!isHMACVerified"
            v-tooltip="$t('CONVERSATION.UNVERIFIED_SESSION')"
            size="14"
            class="patra-conv-head-warn shrink-0"
            icon="warning"
          />
          <button
            type="button"
            class="patra-conv-head-cnum shrink-0"
            :title="$t('CONVERSATION.HEADER.COPY_ID_SUCCESS')"
            @click="copyConversationId"
          >
            #{{ chat.id }}
          </button>
        </div>
        <div class="patra-conv-head-sub">
          <span
            v-if="contactPresence.last_active"
            class="patra-conv-head-live"
            :class="{ 'is-online': contactPresence.online }"
          >
            <span v-if="contactPresence.online" class="patra-conv-head-pip" />
            {{ contactPresence.last_active }}
          </span>
          <template v-if="contactPresence.last_active">
            <span class="patra-conv-head-sep" aria-hidden="true">·</span>
          </template>
          <span class="truncate">
            {{ channelIcon }} {{ inboxDisplayName }}
          </span>
          <template v-if="isSnoozed">
            <span class="patra-conv-head-sep" aria-hidden="true">·</span>
            <span class="patra-conv-head-snooze truncate">
              {{ snoozedDisplayText }}
            </span>
          </template>
        </div>
      </div>
    </div>

    <div class="patra-conv-head-r">
      <SLACardLabel
        v-if="hasSlaPolicyId"
        :chat="chat"
        show-extended-info
        :parent-width="width"
        class="patra-conv-head-sla hidden md:flex"
      />

      <div class="patra-conv-head-util relative">
        <button
          type="button"
          class="patra-conv-head-icon-btn"
          :title="$t('PATRA.MESSAGE_SEARCH.TITLE')"
          :aria-label="$t('PATRA.MESSAGE_SEARCH.TITLE')"
          @click="showMessageSearch = !showMessageSearch"
        >
          <span class="i-lucide-search size-4" />
        </button>
        <ConversationMessageSearch
          v-if="showMessageSearch"
          :conversation-id="chat.id"
          @close="showMessageSearch = false"
        />
      </div>

      <button
        type="button"
        class="patra-conv-head-icon-btn"
        :title="$t('PATRA.INFO_PANEL.TITLE')"
        :aria-label="$t('PATRA.INFO_PANEL.TITLE')"
        @click="showInfoPanel = true"
      >
        <span class="i-lucide-info size-4" />
      </button>
      <ConversationInfoPanel
        :chat="chat"
        :show="showInfoPanel"
        @close="showInfoPanel = false"
      />

      <button
        type="button"
        class="patra-conv-head-ai-toggle"
        :class="{ 'is-off': aiOff }"
        :title="aiToggleLabel"
        :aria-label="aiToggleLabel"
        @click="toggleAiOff"
      >
        <span class="patra-conv-head-ai-spark" aria-hidden="true">
          <svg viewBox="0 0 24 24" fill="currentColor">
            <path
              d="M12 2l2.4 7.4H22l-6 4.6 2.3 7.4L12 17l-6.3 4.4L8 14 2 9.4h7.6z"
            />
          </svg>
        </span>
        {{ aiToggleLabel }}
        <span class="patra-conv-head-ai-sw" aria-hidden="true">
          <i />
        </span>
      </button>

      <button
        type="button"
        class="patra-conv-head-btn"
        :class="{ 'is-pinned': isPinned }"
        :title="
          isPinned
            ? $t('PATRA.CONVERSATION.UNPIN')
            : $t('PATRA.CONVERSATION.PIN')
        "
        :aria-label="
          isPinned
            ? $t('PATRA.CONVERSATION.UNPIN')
            : $t('PATRA.CONVERSATION.PIN')
        "
        @click="togglePin"
      >
        <svg
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          aria-hidden="true"
        >
          <path d="M19 21l-7-5-7 5V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2z" />
        </svg>
        {{ pinButtonLabel }}
      </button>

      <button
        v-if="!aiOff"
        type="button"
        class="patra-conv-head-btn"
        :title="$t('PATRA.CONVERSATION.TAKE_OVER')"
        :aria-label="$t('PATRA.CONVERSATION.TAKE_OVER')"
        @click="takeOver"
      >
        <svg
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          aria-hidden="true"
        >
          <path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2" />
          <circle cx="9" cy="7" r="4" />
          <path d="M20 8v6M23 11h-6" />
        </svg>
        {{ $t('PATRA.CONVERSATION.TAKE_OVER') }}
      </button>

      <MoreActions :conversation-id="currentChat.id" />
    </div>
  </div>
</template>

<style scoped>
.patra-conv-head {
  --ph-surface: #0c0b12;
  --ph-surface-2: #131119;
  --ph-surface-3: #1b1925;
  --ph-surface-4: #252233;
  --ph-border: #171520;
  --ph-border-hi: #2e2940;
  --ph-patra: #6e56cf;
  --ph-patra-2: #8b5cf6;
  --ph-patra-3: #a78bfa;
  --ph-patra-deep: #5b45b0;
  --ph-patra-glow: rgba(110, 86, 207, 0.55);
  --ph-text: #ededf2;
  --ph-text-2: #a8a6b6;
  --ph-text-3: #75727f;
  --ph-text-4: #54515e;
  --ph-green: #3fb950;
  --ph-amber: #e3a008;

  display: flex;
  flex-direction: column;
  align-items: stretch;
  justify-content: space-between;
  gap: 12px;
  flex: 1;
  width: 100%;
  min-width: 0;
  padding: 13px 22px;
  border-bottom: 1px solid var(--ph-border);
  background: color-mix(in srgb, var(--ph-surface) 75%, transparent);
  backdrop-filter: blur(16px);
  position: relative;
  z-index: 5;
}

@media (min-width: 1280px) {
  .patra-conv-head {
    flex-direction: row;
    align-items: center;
    gap: 16px;
    min-height: 68px;
  }
}

.patra-conv-head-l {
  display: flex;
  align-items: center;
  gap: 12px;
  min-width: 0;
  flex: 1;
}

.patra-conv-head-back {
  flex-shrink: 0;
}

.patra-conv-head-avatar {
  flex-shrink: 0;
}

.patra-conv-head-info {
  overflow: hidden;
}

.patra-conv-head-name {
  display: flex;
  align-items: center;
  gap: 7px;
  min-width: 0;
  font-family: 'Space Grotesk', ui-sans-serif, system-ui, sans-serif;
  font-weight: 600;
  font-size: 16px;
  color: var(--ph-text);
  line-height: 1.25;
}

.patra-conv-head-name-text {
  min-width: 0;
}

.patra-conv-head-warn {
  color: var(--ph-amber);
}

.patra-conv-head-cnum {
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  font-size: 12px;
  font-weight: 500;
  color: var(--ph-text-4);
  background: none;
  border: none;
  padding: 0;
  cursor: pointer;
  font-variant-numeric: tabular-nums;
  transition: color 0.2s;
}

.patra-conv-head-cnum:hover {
  color: var(--ph-text-3);
}

.patra-conv-head-sub {
  display: flex;
  align-items: center;
  gap: 7px;
  margin-top: 2px;
  font-size: 12px;
  color: var(--ph-text-3);
  min-width: 0;
  overflow: hidden;
}

.patra-conv-head-sep {
  color: var(--ph-text-4);
  flex-shrink: 0;
}

.patra-conv-head-live {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  flex-shrink: 0;
  color: var(--ph-text-3);
}

.patra-conv-head-live.is-online {
  color: var(--ph-green);
}

.patra-conv-head-pip {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  background: var(--ph-green);
  box-shadow: 0 0 6px var(--ph-green);
  animation: patra-head-pip 2s infinite;
}

@keyframes patra-head-pip {
  0%,
  100% {
    opacity: 1;
    transform: scale(1);
  }

  50% {
    opacity: 0.5;
    transform: scale(0.8);
  }
}

.patra-conv-head-snooze {
  color: var(--ph-amber);
  font-weight: 500;
}

.patra-conv-head-r {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: flex-start;
  gap: 8px;
  flex-shrink: 0;
  width: 100%;
}

@media (min-width: 1280px) {
  .patra-conv-head-r {
    justify-content: flex-end;
    width: auto;
  }
}

.patra-conv-head-icon-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 32px;
  height: 32px;
  border-radius: 9px;
  border: 1px solid var(--ph-border);
  background: var(--ph-surface-2);
  color: var(--ph-text-2);
  cursor: pointer;
  transition: all 0.25s cubic-bezier(0.34, 1.56, 0.64, 1);
}

.patra-conv-head-icon-btn:hover {
  color: #fff;
  border-color: transparent;
  background: linear-gradient(135deg, var(--ph-patra), var(--ph-patra-deep));
  box-shadow: 0 4px 12px var(--ph-patra-glow);
}

.patra-conv-head-ai-toggle {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  font-size: 12.5px;
  font-weight: 600;
  color: var(--ph-patra-3);
  background: linear-gradient(
    135deg,
    rgba(110, 86, 207, 0.16),
    rgba(139, 92, 246, 0.06)
  );
  border: 1px solid rgba(139, 92, 246, 0.32);
  border-radius: 10px;
  padding: 7px 12px;
  cursor: pointer;
  transition: all 0.25s cubic-bezier(0.34, 1.56, 0.64, 1);
  white-space: nowrap;
}

.patra-conv-head-ai-toggle:hover {
  transform: translateY(-2px);
  box-shadow: 0 6px 18px var(--ph-patra-glow);
  border-color: var(--ph-patra);
}

.patra-conv-head-ai-toggle.is-off {
  color: var(--ph-text-3);
  background: var(--ph-surface-2);
  border-color: var(--ph-border);
}

.patra-conv-head-ai-toggle.is-off:hover {
  border-color: var(--ph-border-hi);
  box-shadow: none;
  transform: none;
}

.patra-conv-head-ai-spark svg {
  width: 14px;
  height: 14px;
  animation: patra-head-spark 3s ease-in-out infinite;
}

@keyframes patra-head-spark {
  0%,
  100% {
    opacity: 1;
    transform: scale(1);
  }

  50% {
    opacity: 0.6;
    transform: scale(1.15);
  }
}

.patra-conv-head-ai-sw {
  width: 30px;
  height: 17px;
  border-radius: 10px;
  background: linear-gradient(135deg, var(--ph-patra), var(--ph-patra-2));
  position: relative;
  transition: all 0.3s;
  box-shadow: 0 0 10px var(--ph-patra-glow);
  flex-shrink: 0;
}

.patra-conv-head-ai-sw i {
  position: absolute;
  top: 2px;
  right: 2px;
  width: 13px;
  height: 13px;
  border-radius: 50%;
  background: #fff;
  transition: all 0.3s;
}

.patra-conv-head-ai-toggle.is-off .patra-conv-head-ai-sw {
  background: var(--ph-surface-4);
  box-shadow: none;
}

.patra-conv-head-ai-toggle.is-off .patra-conv-head-ai-sw i {
  right: auto;
  left: 2px;
}

.patra-conv-head-btn {
  display: inline-flex;
  align-items: center;
  gap: 7px;
  font-size: 13px;
  font-weight: 500;
  padding: 8px 14px;
  border-radius: 10px;
  border: 1px solid var(--ph-border);
  background: var(--ph-surface-2);
  color: var(--ph-text);
  cursor: pointer;
  transition: all 0.22s cubic-bezier(0.23, 1, 0.32, 1);
  white-space: nowrap;
}

.patra-conv-head-btn svg {
  width: 15px;
  height: 15px;
  flex-shrink: 0;
}

.patra-conv-head-btn:hover {
  border-color: var(--ph-border-hi);
  background: var(--ph-surface-3);
  transform: translateY(-2px);
  box-shadow: 0 6px 16px rgba(0, 0, 0, 0.25);
}

.patra-conv-head-btn:active {
  transform: translateY(0);
}

.patra-conv-head-btn.is-pinned {
  border-color: rgba(227, 160, 8, 0.35);
  background: rgba(227, 160, 8, 0.12);
  color: var(--ph-amber);
}

.patra-conv-head-r :deep(.resolve-actions) {
  flex-shrink: 0;
}

.patra-conv-head-r :deep(.resolve-actions > div:first-child) {
  border: none !important;
  box-shadow: none !important;
  outline: none !important;
  background: transparent !important;
  border-radius: 0 !important;
}

.patra-conv-head-r :deep(.resolve-actions button) {
  display: inline-flex !important;
  align-items: center !important;
  gap: 7px !important;
  font-size: 13px !important;
  font-weight: 500 !important;
  padding: 8px 14px !important;
  border-radius: 10px !important;
  border: 1px solid transparent !important;
  background: linear-gradient(
    135deg,
    var(--ph-patra),
    var(--ph-patra-deep)
  ) !important;
  color: #fff !important;
  box-shadow: 0 4px 14px var(--ph-patra-glow) !important;
  min-height: unset !important;
  height: auto !important;
  transition: all 0.22s cubic-bezier(0.23, 1, 0.32, 1) !important;
}

.patra-conv-head-r :deep(.resolve-actions button:hover) {
  filter: brightness(1.12);
  box-shadow: 0 7px 22px var(--ph-patra-glow) !important;
  transform: translateY(-2px);
}

.patra-conv-head-r :deep(.resolve-actions button svg) {
  width: 15px;
  height: 15px;
}

.patra-conv-head-r :deep(.actions--container > button:last-of-type),
.patra-conv-head-r :deep(.actions--container > div > button) {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 32px;
  height: 32px;
  border-radius: 9px;
  border: 1px solid var(--ph-border);
  background: var(--ph-surface-2);
  color: var(--ph-text-2);
}

.patra-conv-head-r :deep(.actions--container > button:last-of-type:hover),
.patra-conv-head-r :deep(.actions--container > div > button:hover) {
  color: #fff;
  border-color: transparent;
  background: linear-gradient(135deg, var(--ph-patra), var(--ph-patra-deep));
  box-shadow: 0 4px 12px var(--ph-patra-glow);
}
</style>
