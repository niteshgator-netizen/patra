<script setup>
import { computed, useTemplateRef } from 'vue';
import { getLastMessage } from 'dashboard/helper/conversationHelper';
import CardAvatar from './CardAvatar.vue';
import CardContent from './CardContent.vue';
import CardLabels from './CardLabelsV5.vue';
import CardPriorityIcon from './CardPriorityIcon.vue';
import InboxName from 'dashboard/components-next/Conversation/InboxName.vue';
import Avatar from 'next/avatar/Avatar.vue';
import TimeAgo from 'dashboard/components/ui/TimeAgo.vue';
import SLACardLabel from 'dashboard/components-next/Conversation/Sla/SLACardLabel.vue';
import CardStatusIcon from './CardStatusIcon.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  chat: { type: Object, required: true },
  currentContact: { type: Object, required: true },
  assignee: { type: Object, default: () => ({}) },
  inbox: { type: Object, default: () => ({}) },
  selected: { type: Boolean, default: false },
  isActiveChat: { type: Boolean, default: false },
  showAssignee: { type: Boolean, default: false },
  showInboxName: { type: Boolean, default: false },
  isInboxView: { type: Boolean, default: false },
});

const emit = defineEmits([
  'selectConversation',
  'deSelectConversation',
  'click',
  'contextmenu',
]);

const lastMessageInChat = computed(() => getLastMessage(props.chat));
const showLabelsSection = computed(() => props.chat.labels?.length > 0);

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

const unreadCount = computed(() => props.chat.unread_count);

const slaCardLabel = useTemplateRef('slaCardLabel');

const hasSlaPolicyId = computed(
  () => props.chat?.sla_policy_id || slaCardLabel.value?.hasSlaThreshold
);

const selectedModel = computed({
  get: () => props.selected,
  set: value => {
    if (value) {
      emit('selectConversation', value);
    } else {
      emit('deSelectConversation', value);
    }
  },
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
</script>

<template>
  <div
    class="convo-card-v6 conversation relative cursor-pointer group grid gap-4 items-center px-3 min-h-12"
    :class="{
      active: isActiveChat,
      selected,
      'is-priority': chat.priority === 'urgent' || chat.priority === 'high',
      'grid-cols-[minmax(0,2fr)_minmax(0,1fr)]': showLabelsSection,
      'grid-cols-[minmax(0,2fr)_max-content]': !showLabelsSection,
    }"
    @click="$emit('click', $event)"
    @contextmenu="$emit('contextmenu', $event)"
  >
    <!-- LEFT SECTION -->
    <div class="flex items-center gap-2 min-w-0 flex-1">
      <div class="flex items-center justify-center flex-shrink-0" @click.stop>
        <Checkbox v-model="selectedModel" />
      </div>

      <div class="w-px h-3 bg-n-slate-6 flex-shrink-0" />

      <div class="w-4 flex items-center justify-center flex-shrink-0">
        <CardPriorityIcon :priority="chat.priority" show-empty />
      </div>

      <div class="w-4 flex items-center justify-center flex-shrink-0">
        <Avatar
          v-if="showAssignee && assignee.name"
          v-tooltip.top="{
            content: assignee.name,
            delay: { show: 500, hide: 0 },
          }"
          :name="assignee.name"
          :src="assignee.thumbnail"
          :size="14"
          :status="assignee.availability_status"
          hide-offline-status
        />
        <Icon
          v-else
          icon="i-woot-empty-assignee"
          class="size-4 text-n-slate-7"
        />
      </div>

      <div class="w-4 flex items-center justify-center flex-shrink-0">
        <CardStatusIcon :status="chat.status" show-empty />
      </div>

      <div class="w-px h-3 bg-n-slate-6 flex-shrink-0" />

      <div v-if="!isInboxView && showInboxName" class="w-20 flex-shrink-0">
        <InboxName v-if="showInboxName" :inbox="inbox" class="min-w-0" />
      </div>

      <div
        v-if="!isInboxView && showInboxName"
        class="w-px h-3 bg-n-slate-6 flex-shrink-0"
      />

      <div
        v-tooltip.top="{
          content: chat.id,
          delay: { show: 500, hide: 0 },
        }"
        class="h-6 flex items-center gap-1 max-w-20 w-full min-w-0 flex-shrink-0"
      >
        <Icon
          icon="i-woot-hash"
          class="size-3.5 text-n-slate-10 flex-shrink-0"
        />
        <span class="text-body-main text-n-slate-11 truncate">
          {{ chat.id }}
        </span>
      </div>

      <CardAvatar
        :contact="currentContact"
        :selected="false"
        :enable-selection="false"
        :hide-thumbnail="false"
      />

      <h4
        class="cv6-name text-heading-3 my-0 capitalize truncate text-n-slate-12 font-medium w-32 flex-shrink-0"
      >
        {{ currentContact.name }}
        <span
          v-if="paymentDotClass"
          v-tooltip.top="paymentStatus?.label"
          class="inline-block w-2 h-2 rounded-full ml-1 align-middle shrink-0"
          :class="paymentDotClass"
        />
      </h4>

      <CardContent
        :last-message="lastMessageInChat"
        :voice-call-status="voiceCallData.status"
        :voice-call-direction="voiceCallData.direction"
        :unread-count="unreadCount"
        :show-expanded-preview="false"
      />
    </div>

    <!-- RIGHT SECTION -->
    <div class="flex items-center justify-end gap-1.5 flex-shrink-0">
      <div v-if="showLabelsSection" class="min-w-0 w-full">
        <CardLabels
          :labels="chat.labels"
          disable-toggle
          class="my-0 [&>div]:justify-end justify-end"
        />
      </div>

      <div v-if="hasSlaPolicyId" class="flex-shrink-0">
        <SLACardLabel ref="slaCardLabel" :chat="chat" />
      </div>

      <div class="cv6-time flex-shrink-0 w-[4.375rem] text-end">
        <TimeAgo
          :conversation-id="chat.id"
          :last-activity-timestamp="chat.timestamp"
          :created-at-timestamp="chat.created_at"
          class="font-440 !text-xs text-n-slate-11"
        />
      </div>
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

.cv6-name {
  font-weight: 600;
  font-size: 13.5px;
}

.cv6-time {
  font-size: 11px;
  color: var(--text-3, #75727f);
  font-family: 'JetBrains Mono', ui-monospace, monospace;
}
</style>
