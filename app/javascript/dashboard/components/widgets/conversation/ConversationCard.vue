<script setup>
import { computed, inject, onMounted, onUnmounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';
import { getLastMessage } from 'dashboard/helper/conversationHelper';
import Avatar from 'next/avatar/Avatar.vue';
import MessagePreview from './MessagePreview.vue';
import InboxName from '../InboxName.vue';
import TimeAgo from 'dashboard/components/ui/TimeAgo.vue';
import CardLabels from './conversationCardComponents/CardLabels.vue';
import CardPriorityIcon from 'dashboard/components-next/Conversation/ConversationCard/CardPriorityIcon.vue';
import UnreadBadge from 'dashboard/components-next/Conversation/ConversationCard/UnreadBadge.vue';
import SLACardLabel from './components/SLACardLabel.vue';
import VoiceCallStatus from './VoiceCallStatus.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import LabelDropdown from 'shared/components/ui/label/LabelDropdown.vue';
import wootConstants from 'dashboard/constants/globals';
import { CONVERSATION_PRIORITY } from 'shared/constants/messages';
import PatraConversationsAPI from 'dashboard/api/patraConversations';
import types from 'dashboard/store/mutation-types';
import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';

const props = defineProps({
  chat: { type: Object, required: true },
  currentContact: { type: Object, required: true },
  assignee: { type: Object, default: () => ({}) },
  inbox: { type: Object, default: () => ({}) },
  selected: { type: Boolean, default: false },
  isActiveChat: { type: Boolean, default: false },
  showAssignee: { type: Boolean, default: false },
  showInboxName: { type: Boolean, default: false },
  hideThumbnail: { type: Boolean, default: false },
  compact: { type: Boolean, default: false },
});

const emit = defineEmits([
  'click',
  'contextmenu',
  'selectConversation',
  'deSelectConversation',
  'resolve',
  'snooze',
]);

const { t } = useI18n();
const store = useStore();
const { isAdmin } = useAdmin();

const assignLabels = inject('assignLabels', null);
const removeLabels = inject('removeLabels', null);

const hovered = ref(false);
const showLabelDropdown = ref(false);
const now = ref(Date.now());
let slaTimer = null;

const unreadCount = computed(() => props.chat.unread_count);
const hasUnread = computed(() => unreadCount.value > 0);
const lastMessageInChat = computed(() => getLastMessage(props.chat));

const voiceCallData = computed(() => {
  const last = lastMessageInChat.value;
  if (last?.content_type !== 'voice_call' || !last.call) {
    return { status: null, direction: null };
  }
  return {
    status: last.call.status,
    direction: last.call.direction === 'outgoing' ? 'outbound' : 'inbound',
  };
});

const showMetaSection = computed(() => {
  return (
    props.showInboxName ||
    (props.showAssignee && props.assignee.name) ||
    props.chat.priority
  );
});

const hasSlaPolicyId = computed(() => props.chat?.sla_policy_id);

const conversationLabels = computed(() => props.chat?.labels || []);
const needsAiAttention = computed(() => {
  const labels = conversationLabels.value;
  return labels.includes('ai-off') || labels.includes('needs-human');
});
const aiStatus = computed(() =>
  needsAiAttention.value ? 'needs-attention' : 'ai-on'
);
const aiStatusLabel = computed(() =>
  needsAiAttention.value
    ? t('PATRA.CONVERSATION_CARD.AI_NEEDS_ATTENTION')
    : t('PATRA.CONVERSATION_CARD.AI_HANDLING')
);
const hasVipLabel = computed(() => (props.chat?.labels || []).includes('vip'));

const preferredPlatform = computed(() => {
  return props.currentContact?.custom_attributes?.preferred_platform;
});

const showVipBadge = computed(() => {
  const tier = props.chat?.meta?.sender?.custom_attributes?.loyalty_tier;
  return tier === 'vip';
});

const gameBadgeLabel = computed(() => {
  const platform = preferredPlatform.value;
  if (!platform) return null;
  const name = String(platform)
    .replace(/_/g, ' ')
    .replace(/\b\w/g, c => c.toUpperCase());
  return t('PATRA.CONVERSATION_CARD.GAME_BADGE', { game: name });
});

const paymentStatus = computed(
  () =>
    props.chat?.payment_status ||
    props.chat?.meta?.sender?.payment_status ||
    props.currentContact?.payment_status ||
    null
);

const paymentDotClass = computed(() => {
  const color = paymentStatus.value?.color;
  if (color === 'green') return 'bg-green-500';
  if (color === 'blue') return 'bg-blue-500';
  if (color === 'yellow') return 'bg-amber-500';
  return null;
});

const waitingMinutes = computed(() => {
  const waitingSince = props.chat?.waiting_since;
  if (!waitingSince || waitingSince <= 0) return 0;
  return (now.value - waitingSince * 1000) / 60000;
});

const slaDotColor = computed(() => {
  if (props.chat?.status !== wootConstants.STATUS_TYPE.OPEN) return null;
  if (!props.chat?.waiting_since || props.chat.waiting_since <= 0) return null;
  if (waitingMinutes.value > 5) return 'bg-red-500';
  if (waitingMinutes.value > 3) return 'bg-amber-500';
  return null;
});

const priorityBorderClass = computed(() => {
  const priority = props.chat?.priority;
  if (priority === CONVERSATION_PRIORITY.URGENT) {
    return 'ltr:border-l-[3px] rtl:border-r-[3px] ltr:border-l-red-500 rtl:border-r-red-500';
  }
  if (priority === CONVERSATION_PRIORITY.HIGH) {
    return 'ltr:border-l-[3px] rtl:border-r-[3px] ltr:border-l-amber-500 rtl:border-r-amber-500';
  }
  return '';
});

const isPinned = computed(() => {
  const pinned = props.chat?.additional_attributes?.pinned;
  return pinned === true || pinned === 'true';
});

const accountLabels = computed(() => store.getters['labels/getLabels'] || []);
const savedLabelTitles = computed(() => props.chat?.labels || []);

const sentimentEmoji = computed(() => {
  const sentiment = props.chat?.additional_attributes?.sentiment;
  if (sentiment === 'positive') return '😊';
  if (sentiment === 'negative') return '😡';
  if (sentiment === 'neutral') return '😐';
  return null;
});

const isCustomerOnline = computed(() => {
  const lastMsg =
    props.chat?.messages?.[props.chat.messages.length - 1] ||
    props.chat?.last_non_activity_message;
  if (!lastMsg) return false;
  const createdAt = lastMsg.created_at;
  const timestamp =
    typeof createdAt === 'number' ? createdAt * 1000 : new Date(createdAt).getTime();
  return Date.now() - timestamp < 5 * 60 * 1000;
});

const showLabelsSection = computed(() => {
  return props.chat.labels?.length > 0 || hasSlaPolicyId.value;
});

const messagePreviewClass = computed(() => {
  return [
    hasUnread.value ? 'font-medium text-n-slate-12' : 'text-n-slate-11',
    !props.compact && hasUnread.value ? 'ltr:pr-4 rtl:pl-4' : '',
    props.compact && hasUnread.value ? 'ltr:pr-6 rtl:pl-6' : '',
  ];
});

const onThumbnailHover = () => {
  hovered.value = !props.hideThumbnail;
};

const onThumbnailLeave = () => {
  hovered.value = false;
};

const onSelectConversation = checked => {
  if (checked) {
    emit('selectConversation', props.chat.id, props.inbox.id);
  } else {
    emit('deSelectConversation', props.chat.id, props.inbox.id);
  }
};

const selectedModel = computed({
  get: () => props.selected,
  set: value => onSelectConversation(value),
});

const togglePin = async () => {
  const id = Number(props.chat?.id);
  if (!id) return;
  try {
    const { data } = await PatraConversationsAPI.togglePin(id);
    store.commit(types.UPDATE_CONVERSATION, {
      ...props.chat,
      id,
      updated_at: Math.max(
        Number(data.updated_at) || 0,
        Number(props.chat.updated_at) || 0,
        Math.floor(Date.now() / 1000)
      ),
      additional_attributes: {
        ...(props.chat.additional_attributes || {}),
        pinned: Boolean(data.pinned),
      },
    });
  } catch {
    useAlert(t('PATRA.CONVERSATION.PIN_ERROR'));
  }
};

const toggleLabelDropdown = () => {
  showLabelDropdown.value = !showLabelDropdown.value;
};

const closeLabelDropdown = () => {
  showLabelDropdown.value = false;
};

const addLabelToConversation = label => {
  if (assignLabels) {
    assignLabels([label.title], [props.chat.id]);
  } else {
    store.dispatch('bulkActions/process', {
      type: 'Conversation',
      ids: [props.chat.id],
      labels: { add: [label.title] },
    });
  }
  closeLabelDropdown();
};

const removeLabelFromConversation = label => {
  if (removeLabels) {
    removeLabels([label.title], [props.chat.id]);
  } else {
    store.dispatch('bulkActions/process', {
      type: 'Conversation',
      ids: [props.chat.id],
      labels: { remove: [label.title] },
    });
  }
};

const startSlaTimer = () => {
  if (slaTimer) clearInterval(slaTimer);
  if (
    props.chat?.status === wootConstants.STATUS_TYPE.OPEN &&
    props.chat?.waiting_since > 0
  ) {
    slaTimer = setInterval(() => {
      now.value = Date.now();
    }, 60000);
  }
};

watch(
  () => props.chat.id,
  () => {
    hovered.value = false;
    showLabelDropdown.value = false;
    startSlaTimer();
  }
);

watch(
  () => [props.chat.status, props.chat.waiting_since],
  () => startSlaTimer()
);

onMounted(startSlaTimer);
onUnmounted(() => {
  if (slaTimer) clearInterval(slaTimer);
});

const onCardMouseMove = (e) => {
  const el = e.currentTarget;
  const r = el.getBoundingClientRect();
  el.style.setProperty('--mx', (e.clientX - r.left) + 'px');
  el.style.setProperty('--my', (e.clientY - r.top) + 'px');
};
</script>

<template>
  <div
    class="convo-card-v6 conversation group relative flex items-start flex-grow-0 flex-shrink-0 w-auto max-w-full cursor-pointer"
    :class="[
      {
        active: isActiveChat,
        selected,
        'is-priority': chat.priority === 'urgent' || chat.priority === 'high',
        'px-0': compact,
        'px-3': !compact,
      },
    ]"
    @click="$emit('click', $event)"
    @contextmenu="$emit('contextmenu', $event)"
    @mousemove="onCardMouseMove"
  >
    <!-- QA quick actions (show on hover) -->
    <div class="patra-convo-qa">
      <button
        type="button"
        class="patra-qa"
        :title="$t('PATRA.CONVERSATION_CARD.RESOLVE')"
        @click.stop="$emit('resolve')"
      >
        ✓
      </button>
      <button
        type="button"
        class="patra-qa"
        :title="$t('PATRA.CONVERSATION_CARD.SNOOZE')"
        @click.stop="$emit('snooze')"
      >
        ⏰
      </button>
    </div>
    <div
      class="cv6-avatar relative inline-block shrink-0"
      @mouseenter="onThumbnailHover"
      @mouseleave="onThumbnailLeave"
    >
      <Avatar
        v-if="!hideThumbnail"
        :name="currentContact.name"
        :src="currentContact.thumbnail"
        :size="32"
        :status="currentContact.availability_status"
        :class="!showInboxName ? 'mt-4' : 'mt-8'"
        hide-offline-status
      >
        <template #overlay="{ size }">
          <label
            v-if="hovered || selected"
            class="flex items-center justify-center rounded-full cursor-pointer absolute inset-0 z-10 backdrop-blur-[2px]"
            :style="{ width: `${size}px`, height: `${size}px` }"
            @click.stop
          >
            <Checkbox v-model="selectedModel" />
          </label>
        </template>
      </Avatar>
      <span
        v-if="slaDotColor"
        class="absolute top-0 ltr:left-0 rtl:right-0 w-[10px] h-[10px] rounded-full border-2 border-n-background z-[3]"
        :class="slaDotColor"
        :title="$t('PATRA.CONVERSATION_CARD.SLA_WAITING')"
      />
      <span
        v-if="isCustomerOnline"
        class="absolute bottom-0 ltr:right-0 rtl:left-0 w-[11px] h-[11px] bg-green-500 rounded-full border-2 border-white dark:border-[#16161d] z-[2]"
      />
    </div>
    <div class="px-0 py-3 flex-1 min-w-0 border-line">
      <div
        v-if="showMetaSection"
        class="flex items-center min-w-0 gap-1 ltr:pr-16 rtl:pl-16"
        :class="{
          'ltr:ml-2 rtl:mr-2': !compact,
          'mx-2': compact,
        }"
      >
        <InboxName v-if="showInboxName" :inbox="inbox" class="flex-1 min-w-0" />
        <div
          class="flex items-baseline gap-2 flex-shrink-0"
          :class="{
            'flex-1 justify-between': !showInboxName,
          }"
        >
          <span
            v-if="showAssignee && assignee.name"
            class="text-n-slate-11 text-xs font-medium leading-3 py-0.5 px-0 inline-flex items-center truncate"
          >
            <fluent-icon icon="person" size="12" class="text-n-slate-11" />
            {{ assignee.name }}
          </span>
          <CardPriorityIcon
            :priority="chat.priority"
            class="flex-shrink-0 !size-3.5"
          />
        </div>
      </div>
      <h4
        class="cv6-name conversation--user my-0 mx-2 capitalize pt-0.5 flex-1 min-w-0 ltr:pr-16 rtl:pl-16 text-n-slate-12"
        :class="hasUnread ? 'font-semibold' : 'font-medium'"
      >
        {{ currentContact.name }}
        <span
          v-if="paymentDotClass"
          v-tooltip.top="paymentStatus?.label"
          class="inline-block w-2 h-2 rounded-full ml-1 align-middle shrink-0"
          :class="paymentDotClass"
        />
        <span v-if="sentimentEmoji" class="ml-1">{{ sentimentEmoji }}</span>
        <span
          v-if="gameBadgeLabel"
          class="ml-1 text-[10px] font-medium normal-case text-n-slate-11"
        >
          {{ gameBadgeLabel }}
        </span>
        <span v-if="showVipBadge" class="cv6-tag vip vip-badge">
          ⭐ {{ $t('PATRA.CONVERSATION_CARD.VIP_BADGE') }}
        </span>
      </h4>
      <VoiceCallStatus
        v-if="voiceCallData.status"
        key="voice-status-row"
        :status="voiceCallData.status"
        :direction="voiceCallData.direction"
        :message-preview-class="messagePreviewClass"
      />
      <MessagePreview
        v-else-if="lastMessageInChat"
        key="message-preview"
        :message="lastMessageInChat"
        class="cv6-preview my-0 mx-2 flex-1 min-w-0"
        :class="messagePreviewClass"
      />
      <p
        v-else
        key="no-messages"
        class="cv6-preview text-n-slate-11 my-0 mx-2 flex-1 min-w-0"
        :class="messagePreviewClass"
      >
        <fluent-icon
          size="16"
          class="-mt-0.5 align-middle inline-block text-n-slate-10"
          icon="info"
        />
        <span class="mx-0.5">
          {{ $t(`CHAT_LIST.NO_MESSAGES`) }}
        </span>
      </p>
      <div class="mx-2">
        <span class="cv6-tag ai status-pill" :class="aiStatus">
          <span class="dot" />
          {{ aiStatusLabel }}
        </span>
      </div>
      <div
        class="cv6-meta absolute flex flex-col items-end ltr:right-3 rtl:left-3 z-[1]"
        :class="showMetaSection ? 'top-8' : 'top-4'"
      >
        <span class="cv6-time font-normal leading-4 text-xxs text-n-slate-11 [&_div]:text-n-slate-11">
          <TimeAgo
            :last-activity-timestamp="chat.timestamp"
            :created-at-timestamp="chat.created_at"
            :conversation-id="chat.id"
          />
        </span>
        <UnreadBadge
          v-if="hasUnread"
          :count="unreadCount"
          class="cv6-unread ltr:ml-auto rtl:mr-auto mt-1"
        />
      </div>
      <div
        class="absolute bottom-2 ltr:right-2 rtl:left-2 flex gap-1 opacity-0 group-hover:opacity-100 transition-opacity z-[2]"
        @click.stop
      >
        <button
          type="button"
          class="flex items-center justify-center w-7 h-7 rounded-md bg-n-solid-2 border border-n-weak text-n-slate-12 hover:bg-n-solid-3 dark:bg-n-alpha-3 dark:hover:bg-n-alpha-4 text-sm"
          :title="
            isPinned
              ? $t('PATRA.CONVERSATION.UNPIN')
              : $t('PATRA.CONVERSATION.PIN')
          "
          @click="togglePin"
        >
          📌
        </button>
        <div class="relative">
          <button
            type="button"
            class="flex items-center justify-center w-7 h-7 rounded-md bg-n-solid-2 border border-n-weak text-n-slate-12 hover:bg-n-solid-3 dark:bg-n-alpha-3 dark:hover:bg-n-alpha-4 text-sm"
            :title="$t('PATRA.CONVERSATION_CARD.LABEL')"
            @click="toggleLabelDropdown"
          >
            🏷️
          </button>
          <div
            v-if="showLabelDropdown"
            v-on-clickaway="closeLabelDropdown"
            class="absolute bottom-full mb-1 ltr:right-0 rtl:left-0 w-56 rounded-lg border border-n-strong bg-n-alpha-3 backdrop-blur-[100px] shadow-lg p-2 z-[9999]"
            @click.stop
          >
            <LabelDropdown
              :account-labels="accountLabels"
              :selected-labels="savedLabelTitles"
              :allow-creation="isAdmin"
              @add="addLabelToConversation"
              @remove="removeLabelFromConversation"
            />
          </div>
        </div>
      </div>
      <CardLabels
        v-if="showLabelsSection"
        :conversation-labels="chat.labels"
        class="mt-0.5 mx-2 mb-0"
      >
        <template v-if="hasSlaPolicyId" #before>
          <SLACardLabel :chat="chat" class="ltr:mr-1 rtl:ml-1" />
        </template>
      </CardLabels>
    </div>
  </div>
</template>

<style scoped>
.convo-card-v6 {
  padding: 11px;
  border-radius: 13px;
  cursor: pointer;
  border: 1px solid transparent;
  margin-bottom: 3px;
  transition: all 0.22s cubic-bezier(0.23, 1, 0.32, 1);
  position: relative;
  overflow: hidden;
  background: transparent;
}

.convo-card-v6::before {
  content: none;
}

.convo-card-v6:hover {
  background: var(--surface-2, #131119);
  transform: translateX(3px) scale(1.01);
}

.convo-card-v6.active {
  background: var(--surface-2, #131119);
  border-color: var(--border-hi, #2e2940);
  box-shadow:
    0 0 0 1px rgba(110, 86, 207, 0.15),
    0 8px 24px -8px var(--patra-glow, rgba(110, 86, 207, 0.55));
}

.convo-card-v6.selected:not(.active) {
  background: var(--surface-2, #131119);
}

.convo-card-v6.is-priority::before {
  content: '';
  position: absolute;
  left: 0;
  top: 11px;
  bottom: 11px;
  width: 3px;
  border-radius: 3px;
  background: linear-gradient(180deg, var(--red, #f85149), var(--amber, #e3a008));
}

.convo-card-v6.active::before {
  content: '';
  position: absolute;
  left: 0;
  top: 11px;
  bottom: 11px;
  width: 3px;
  border-radius: 3px;
  background: linear-gradient(
    180deg,
    var(--patra, #6e56cf),
    var(--patra-2, #8b5cf6)
  );
  box-shadow: 0 0 8px var(--patra-glow, rgba(110, 86, 207, 0.55));
}

.convo-card-v6.is-priority.active::before {
  background: linear-gradient(
    180deg,
    var(--patra, #6e56cf),
    var(--patra-2, #8b5cf6)
  );
}

.cv6-avatar :deep(span),
.cv6-avatar :deep(.avatar) {
  width: 40px !important;
  height: 40px !important;
}

/* Root-cause dot fix: the rule above force-sizes EVERY span in the avatar box
   to 40px. The SLA waiting dot is the only bg-red-500 span here, so pin it back
   to 10px without touching the avatar sizing. */
.cv6-avatar :deep(span.bg-red-500) {
  width: 10px !important;
  height: 10px !important;
}

.cv6-name {
  font-weight: 600;
  font-size: 13.5px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.cv6-time {
  font-size: 11px;
  color: var(--text-3, #75727f);
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  flex-shrink: 0;
}

.cv6-preview {
  font-size: 12.5px;
  color: var(--text-2, #a8a6b6);
  line-height: 1.45;
  display: -webkit-box;
  -webkit-line-clamp: 2;
  line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
}

.cv6-tag {
  font-size: 10px;
  font-weight: 600;
  padding: 2px 7px;
  border-radius: 6px;
  white-space: nowrap;
}

.cv6-tag.vip {
  background: rgba(227, 160, 8, 0.16);
  color: var(--amber, #e3a008);
}

.cv6-tag.ai {
  background: rgba(110, 86, 207, 0.18);
  color: var(--patra-3, #a78bfa);
}

.cv6-tag.ai.needs-attention {
  background: rgba(248, 81, 73, 0.16);
  color: var(--red, #f85149);
}

.cv6-tag.new {
  background: rgba(63, 185, 80, 0.16);
  color: var(--green, #3fb950);
}

.cv6-tag.cashout {
  background: rgba(88, 166, 255, 0.16);
  color: var(--blue, #58a6ff);
}

.cv6-unread {
  min-width: 17px !important;
  height: 17px !important;
  padding: 0 4px !important;
  border-radius: 9px !important;
  background: var(--red, #f85149) !important;
  color: #fff !important;
  font-size: 9px !important;
  font-weight: 700 !important;
  font-family: 'JetBrains Mono', ui-monospace, monospace !important;
  border: 2px solid var(--surface, #0c0b12) !important;
  box-shadow: none !important;
}

.convo-card-v6 :deep(.cv6-unread) {
  min-width: 17px;
  height: 17px;
}
</style>
