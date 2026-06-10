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
const currentUser = computed(() => store.getters.getCurrentUser);
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
  fetchConversationWatchers();
});

onBeforeUnmount(() => {
  if (presencePollTimer) clearInterval(presencePollTimer);
});

watch(
  () => [props.chat?.id, props.chat?.meta?.sender?.id],
  () => {
    contactPresence.value = { online: false, last_active: null };
    startPresencePolling();
    fetchConversationWatchers();
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

const pinnedNote = computed(() => {
  const attrs = currentChat.value?.additional_attributes || {};
  return attrs.pinned_note || (attrs.pinned ? 'Conversation pinned by agent' : null);
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

const conversationWatchers = computed(
  () =>
    store.getters['conversationWatchers/getByConversationId'](
      currentChat.value?.id
    ) || []
);

const otherParticipants = computed(() => {
  const metaAgents = currentChat.value?.meta?.agents;
  const metaParticipants =
    currentChat.value?.meta?.all_count > 1 ? metaAgents || [] : [];
  const participants =
    metaParticipants.length > 0 ? metaParticipants : conversationWatchers.value;
  if (participants.length <= 1) return [];
  return participants.filter(a => a.id !== currentUser.value?.id);
});

/* C3: real typing events only — other AGENTS typing in this conversation
   (action-cable fed conversationTypingStatus store). */
const isOtherAgentTyping = computed(() => {
  if (!currentChat.value?.id) return false;
  const userList =
    store.getters['conversationTypingStatus/getUserList'](
      currentChat.value.id
    ) || [];
  return userList.some(
    u => u.type !== 'contact' && u.id !== currentUser.value?.id
  );
});

const autoReplyEnabled = computed(
  () => currentChat.value?.additional_attributes?.auto_reply !== false
);

const toggleAutoReply = async () => {
  const attrs = {
    ...(currentChat.value?.additional_attributes || {}),
    auto_reply: !autoReplyEnabled.value,
  };
  try {
    await store.dispatch('updateCustomAttributes', {
      conversationId: currentChat.value.id,
      customAttributes: attrs,
    });
  } catch (e) {
    console.error('Auto-reply toggle failed', e);
  }
};

const fetchConversationWatchers = () => {
  const conversationId = currentChat.value?.id;
  if (!conversationId) return;
  store.dispatch('conversationWatchers/show', { conversationId });
};
</script>

<template>
  <div ref="conversationHeader" class="patra-conv-head pat-conv-head-v6">
    <div class="pat-conv-head-v6-row">
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
            class="patra-conv-head-cnum conv-id shrink-0"
            :title="$t('CONVERSATION.HEADER.COPY_ID_SUCCESS')"
            @click="copyConversationId"
          >
            #{{ chat.id }}
          </button>
          <div v-if="otherParticipants.length" class="patra-participants">
            <span
              v-for="p in otherParticipants"
              :key="p.id"
              class="patra-participant-dot"
              :title="p.name"
            >
              {{ p.name?.charAt(0) }}
            </span>
            <span class="patra-participants-text">
              {{ $t('PATRA.CONVERSATION.ALSO_VIEWING') }}<template v-if="isOtherAgentTyping">
                {{ $t('PATRA.CONVERSATION.TYPING_SUFFIX') }}</template
              >
            </span>
          </div>
        </div>
        <div class="patra-conv-head-sub">
          <span
            v-if="contactPresence.last_active"
            class="patra-conv-head-live"
            :class="{ 'is-online': contactPresence.online }"
          >
            <span
              v-if="contactPresence.online"
              class="patra-conv-head-pip conv-online-pip"
            />
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
        <span class="pat-hbtn-label">{{ aiToggleLabel }}</span>
        <span class="patra-conv-head-ai-sw pat-ai-sw" aria-hidden="true">
          <i />
        </span>
      </button>

      <button
        type="button"
        class="patra-auto-reply-toggle"
        :class="{ active: autoReplyEnabled }"
        @click="toggleAutoReply"
      >
        <span class="pat-hbtn-label">Auto-reply {{ autoReplyEnabled ? 'on' : 'off' }}</span>
      </button>

      <button
        type="button"
        class="patra-conv-head-btn pat-hbtn"
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
        <span class="pat-hbtn-label">{{ pinButtonLabel }}</span>
      </button>

      <button
        v-if="!aiOff"
        type="button"
        class="patra-conv-head-btn pat-hbtn"
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
        <span class="pat-hbtn-label">{{ $t('PATRA.CONVERSATION.TAKE_OVER') }}</span>
      </button>

      <MoreActions :conversation-id="currentChat.id" />
    </div>
    </div>

    <div v-if="pinnedNote" class="patra-pinned-banner">
      <span class="patra-pinned-icon">📌</span>
      <span class="patra-pinned-label">{{ $t('PATRA.CONVERSATION.PINNED_LABEL') }}</span>
      <span class="patra-pinned-text">{{ pinnedNote }}</span>
    </div>

    <div v-if="hasSlaPolicyId" class="pat-subbar">
      <SLACardLabel
        :chat="chat"
        show-extended-info
        :parent-width="width"
        class="patra-conv-head-sla"
      />
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

/* A4 root cause: the --ph-* tokens above are DARK values on the bare header
   class, so every descendant (pin/take-over buttons, AI toggle off-state,
   more-actions trigger) resolved dark surfaces in light mode. Light values: */
body:not(.dark) .patra-conv-head {
  --ph-surface: #ffffff;
  --ph-surface-2: #f2f0f7;
  --ph-surface-3: #ece9f2;
  --ph-surface-4: #dddae5;
  --ph-border: #e5e3eb;
  --ph-border-hi: #d6d3de;
  --ph-patra-glow: rgba(110, 86, 207, 0.28);
  --ph-text: #1a1a24;
  --ph-text-2: #4a4756;
  --ph-text-3: #75727f;
  --ph-text-4: #a0a0ab;
  --ph-green: #1a7f37;
  --ph-amber: #9a6700;
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
  min-width: 140px;
  flex: 1 1 auto;
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
  flex-wrap: nowrap;
  align-items: center;
  justify-content: flex-start;
  gap: 8px;
  flex-shrink: 1;
  min-width: 0;
  width: 100%;
}

@media (min-width: 1280px) {
  .patra-conv-head-r {
    justify-content: flex-end;
    width: auto;
  }
}

/* Responsive header: progressively simplify instead of wrapping */
/* Tablet and below: hide button text labels, keep icons */
@media (max-width: 1100px) {
  .pat-hbtn-label {
    display: none;
  }
  .patra-conv-head-ai-toggle,
  .patra-auto-reply-toggle,
  .patra-conv-head-btn {
    padding-left: 9px;
    padding-right: 9px;
  }
}

/* Phone: hide low-priority Pin + Take over (MoreActions ⋮ remains as overflow) */
@media (max-width: 760px) {
  .patra-conv-head-btn.pat-hbtn {
    display: none;
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

/* Light mode: the --ph-* vars above are dark-only, so the resting icon button
   stays a dark box on the light header. Give it a light surface. Hover (purple
   gradient + white) is correct in both modes and is left untouched. */
body:not(.dark) .patra-conv-head-icon-btn {
  background: #ffffff;
  border: 1px solid var(--border, #e5e3ee);
  color: var(--text-2, #4a4756);
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

/* ── v6 header bar ── */
.pat-conv-head-v6 {
  flex-shrink: 0;
  position: relative;
  z-index: 2;
}
.pat-conv-head-v6-row {
  flex: 1 1 auto;
  width: 100%;
  min-width: 0;
  padding: 12px 18px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  border-bottom: 1px solid var(--border, #171520);
  background: var(--surface, #0C0B12);
  gap: 12px;
}

/* ── Contact name ── */
.pat-conv-head-v6 .patra-conv-head-name,
.pat-conv-head-v6 .conv-contact-name {
  font-family: 'Space Grotesk', sans-serif;
  font-weight: 600;
  font-size: 15px;
  color: var(--text, #EDEDF2);
}

/* ── Conversation ID ── */
.pat-conv-head-v6 .conv-id {
  font-size: 12px;
  color: var(--text-3, #75727F);
  font-family: 'JetBrains Mono', monospace;
}

/* ── Sub-line ── */
.pat-conv-head-v6 .patra-conv-head-sub {
  font-size: 12px;
  color: var(--text-2, #A8A6B6);
  margin-top: 2px;
}

/* ── Online pip ── */
.pat-conv-head-v6 .conv-online-pip,
.pat-conv-head-v6 .patra-conv-head-pip {
  width: 7px;
  height: 7px;
  border-radius: 50%;
  background: var(--green, #3FB950);
  display: inline-block;
  box-shadow: 0 0 6px var(--green, #3FB950);
  animation: pipPulse 2s ease-in-out infinite;
  flex-shrink: 0;
}
@keyframes pipPulse {
  0%, 100% { opacity: 1; }
  50% { opacity: 0.5; }
}

/* ── AI toggle pill ── */
.patra-conv-head-ai-toggle {
  display: flex !important;
  align-items: center;
  gap: 8px;
  padding: 7px 14px;
  border-radius: 22px;
  background: linear-gradient(135deg, var(--patra, #6E56CF), var(--patra-deep, #5B45B0)) !important;
  color: #fff !important;
  font-size: 12px;
  font-weight: 600;
  cursor: pointer;
  box-shadow: 0 4px 14px var(--patra-glow, rgba(110,86,207,0.55));
  border: none !important;
  transition: all .25s;
  white-space: nowrap;
  font-family: 'Inter', sans-serif;
}
.patra-conv-head-ai-toggle.is-off {
  background: var(--surface-3, #1B1925) !important;
  color: var(--text-2, #A8A6B6) !important;
  box-shadow: none !important;
  border: 1px solid var(--border-hi, #2E2940) !important;
}
.pat-ai-sw {
  width: 28px;
  height: 16px;
  border-radius: 9px;
  background: rgba(255,255,255,.25);
  position: relative;
  flex-shrink: 0;
}
.pat-ai-sw i {
  position: absolute;
  top: 2px;
  right: 2px;
  width: 12px;
  height: 12px;
  border-radius: 50%;
  background: #fff;
  transition: right .2s, left .2s;
}
.patra-conv-head-ai-toggle.is-off .pat-ai-sw i {
  right: unset;
  left: 2px;
}

/* ── Action buttons ── */
.pat-conv-head-v6 .pat-hbtn,
.pat-conv-head-v6 .patra-conv-head-btn {
  height: 32px;
  padding: 0 12px;
  border-radius: 9px;
  border: 1px solid var(--border-hi, #2E2940);
  background: var(--surface-3, #1B1925);
  color: var(--text-2, #A8A6B6);
  font-size: 12px;
  font-weight: 500;
  cursor: pointer;
  white-space: nowrap;
  display: inline-flex;
  align-items: center;
  gap: 6px;
  transition: all .2s;
  font-family: 'Inter', sans-serif;
}
.pat-conv-head-v6 .pat-hbtn:hover,
.pat-conv-head-v6 .patra-conv-head-btn:hover {
  background: var(--surface-4, #252233);
  color: var(--text, #EDEDF2);
  transform: translateY(-1px);
}

/* Resolve = green primary */
.pat-conv-head-v6 .pat-hbtn.primary {
  background: linear-gradient(135deg, var(--green, #3FB950), #2A7F37);
  color: #fff;
  border-color: transparent;
  box-shadow: 0 3px 10px rgba(63,185,80,.3);
}
.pat-conv-head-v6 .pat-hbtn.primary:hover {
  box-shadow: 0 5px 16px rgba(63,185,80,.4);
  transform: translateY(-1px);
}

.pat-conv-head-v6 .patra-conv-head-r :deep(.resolve-actions button) {
  height: 32px !important;
  padding: 0 12px !important;
  border-radius: 9px !important;
  border: 1px solid transparent !important;
  background: linear-gradient(135deg, var(--green, #3FB950), #2A7F37) !important;
  color: #fff !important;
  font-size: 12px !important;
  font-weight: 500 !important;
  box-shadow: 0 3px 10px rgba(63, 185, 80, 0.3) !important;
  font-family: 'Inter', sans-serif !important;
}
.pat-conv-head-v6 .patra-conv-head-r :deep(.resolve-actions button:hover) {
  box-shadow: 0 5px 16px rgba(63, 185, 80, 0.4) !important;
  transform: translateY(-1px) !important;
  filter: none !important;
}

/* ── SLA sub-bar ── */
.pat-subbar {
  padding: 5px 18px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  border-bottom: 1px solid var(--border, #171520);
  background: var(--surface, #0C0B12);
  font-size: 12px;
  flex-shrink: 0;
}
.pat-subbar :deep(.patra-conv-head-sla) {
  color: var(--amber, #E3A008);
  font-size: 12px;
  font-weight: 500;
  background: transparent;
  border: none;
  padding: 0;
}

.patra-participants {
  display: flex;
  align-items: center;
  gap: 4px;
  font-size: 10px;
  color: #75727f;
  margin-left: 8px;
  flex-shrink: 0;
}

.patra-participant-dot {
  width: 18px;
  height: 18px;
  border-radius: 50%;
  background: rgba(110, 86, 207, 0.2);
  color: #a78bfa;
  font-size: 9px;
  display: flex;
  align-items: center;
  justify-content: center;
  font-weight: 600;
}

.patra-participants-text {
  white-space: nowrap;
}

.patra-auto-reply-toggle {
  font-size: 10px;
  padding: 2px 8px;
  border-radius: 10px;
  border: 1px solid rgba(110, 86, 207, 0.2);
  background: transparent;
  color: #75727f;
  cursor: pointer;
  white-space: nowrap;
}

.patra-auto-reply-toggle.active {
  background: rgba(110, 86, 207, 0.12);
  color: #a78bfa;
}

.patra-pinned-banner {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 6px 12px;
  background: rgba(110, 86, 207, 0.06);
  border-bottom: 1px solid rgba(110, 86, 207, 0.12);
  font-size: 12px;
  /* A3/A4: tokenized — hardcoded dark-theme hex washed out in light */
  color: var(--patra-3, #a78bfa);
}

.patra-pinned-icon {
  font-size: 14px;
}

.patra-pinned-label {
  font-weight: 600;
  color: var(--patra-2, #8b5cf6);
}

.patra-pinned-text {
  color: var(--text, #1a1a24);
  flex: 1;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
</style>
