<script setup>
import { computed } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { messageTimestamp } from 'shared/helpers/timeHelper';
import SidebarActionsHeader from 'dashboard/components-next/SidebarActionsHeader.vue';
import SLACardLabel from './components/SLACardLabel.vue';
import CardPriorityIcon from 'dashboard/components-next/Conversation/ConversationCard/CardPriorityIcon.vue';

const props = defineProps({
  chat: { type: Object, required: true },
  show: { type: Boolean, default: false },
});

const emit = defineEmits(['close']);

const { t } = useI18n();
const store = useStore();

const inbox = computed(() =>
  store.getters['inboxes/getInbox'](props.chat.inbox_id)
);
const contact = computed(() =>
  store.getters['contacts/getContact'](props.chat.meta?.sender?.id)
);
const assignee = computed(() => props.chat.meta?.assignee);
const createdAt = computed(() =>
  props.chat.created_at
    ? messageTimestamp(props.chat.created_at, 'LLL d, yyyy h:mm a')
    : '—'
);
const channelType = computed(() => inbox.value?.channel_type || '—');
const labels = computed(() => props.chat.labels || []);
</script>

<template>
  <Teleport to="body">
    <div
      v-if="show"
      class="fixed inset-0 z-50 flex justify-end bg-n-alpha-black2"
      @click.self="emit('close')"
    >
      <aside
        class="flex h-full w-full max-w-sm flex-col border-l border-n-weak bg-n-solid-1 shadow-xl"
        @click.stop
      >
        <SidebarActionsHeader
          :title="$t('PATRA.INFO_PANEL.TITLE')"
          @close="emit('close')"
        />
        <div class="flex-1 overflow-y-auto px-4 py-3 space-y-4 text-sm">
          <section>
            <h3 class="mb-2 text-xs font-semibold uppercase text-n-slate-11">
              {{ $t('PATRA.INFO_PANEL.CONVERSATION') }}
            </h3>
            <dl class="space-y-2">
              <div class="flex justify-between gap-2">
                <dt class="text-n-slate-11">{{ $t('PATRA.INFO_PANEL.CREATED') }}</dt>
                <dd class="text-n-slate-12 text-right">{{ createdAt }}</dd>
              </div>
              <div class="flex justify-between gap-2">
                <dt class="text-n-slate-11">{{ $t('PATRA.INFO_PANEL.CHANNEL') }}</dt>
                <dd class="text-n-slate-12 text-right truncate">{{ channelType }}</dd>
              </div>
              <div class="flex justify-between gap-2">
                <dt class="text-n-slate-11">{{ $t('PATRA.INFO_PANEL.INBOX') }}</dt>
                <dd class="text-n-slate-12 text-right">{{ inbox?.name || '—' }}</dd>
              </div>
              <div class="flex items-center justify-between gap-2">
                <dt class="text-n-slate-11">{{ $t('PATRA.INFO_PANEL.PRIORITY') }}</dt>
                <dd><CardPriorityIcon :priority="chat.priority" /></dd>
              </div>
              <div v-if="chat.sla_policy_id" class="flex justify-between gap-2">
                <dt class="text-n-slate-11">{{ $t('PATRA.INFO_PANEL.SLA') }}</dt>
                <dd><SLACardLabel :chat="chat" /></dd>
              </div>
              <div class="flex justify-between gap-2">
                <dt class="text-n-slate-11">{{ $t('PATRA.INFO_PANEL.AGENT') }}</dt>
                <dd class="text-n-slate-12 text-right">
                  {{ assignee?.name || $t('PATRA.INFO_PANEL.UNASSIGNED') }}
                </dd>
              </div>
            </dl>
          </section>

          <section v-if="labels.length">
            <h3 class="mb-2 text-xs font-semibold uppercase text-n-slate-11">
              {{ $t('PATRA.INFO_PANEL.LABELS') }}
            </h3>
            <div class="flex flex-wrap gap-1">
              <span
                v-for="label in labels"
                :key="label"
                class="rounded-full border border-n-weak px-2 py-0.5 text-xs text-n-slate-12"
              >
                {{ label }}
              </span>
            </div>
          </section>

          <section>
            <h3 class="mb-2 text-xs font-semibold uppercase text-n-slate-11">
              {{ $t('PATRA.INFO_PANEL.CONTACT') }}
            </h3>
            <dl class="space-y-2">
              <div class="flex justify-between gap-2">
                <dt class="text-n-slate-11">{{ $t('PATRA.INFO_PANEL.NAME') }}</dt>
                <dd class="text-n-slate-12 text-right">{{ contact?.name || '—' }}</dd>
              </div>
              <div v-if="contact?.email" class="flex justify-between gap-2">
                <dt class="text-n-slate-11">{{ $t('PATRA.INFO_PANEL.EMAIL') }}</dt>
                <dd class="text-n-slate-12 text-right truncate">{{ contact.email }}</dd>
              </div>
              <div v-if="contact?.phone_number" class="flex justify-between gap-2">
                <dt class="text-n-slate-11">{{ $t('PATRA.INFO_PANEL.PHONE') }}</dt>
                <dd class="text-n-slate-12 text-right">{{ contact.phone_number }}</dd>
              </div>
            </dl>
          </section>
        </div>
      </aside>
    </div>
  </Teleport>
</template>
