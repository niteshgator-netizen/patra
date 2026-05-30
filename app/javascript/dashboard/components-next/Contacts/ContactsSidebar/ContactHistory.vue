<script setup>
import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';

import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ConversationCard from 'dashboard/components-next/Conversation/ConversationCard/ConversationCard.vue';

const { t } = useI18n();
const route = useRoute();

const conversations = useMapGetter(
  'contactConversations/getAllConversationsByContactId'
);
const contactsById = useMapGetter('contacts/getContactById');
const stateInbox = useMapGetter('inboxes/getInboxById');
const accountLabels = useMapGetter('labels/getLabels');

const accountLabelsValue = computed(() => accountLabels.value);

const uiFlags = useMapGetter('contactConversations/getUIFlags');
const isFetching = computed(() => uiFlags.value.isFetching);

const contactConversations = computed(() =>
  conversations.value(route.params.contactId)
);
</script>

<template>
  <div v-if="isFetching" class="tab-loading">
    <Spinner />
  </div>
  <div v-else-if="contactConversations.length > 0" class="history-list">
    <ConversationCard
      v-for="conversation in contactConversations"
      :key="conversation.id"
      :conversation="conversation"
      :contact="contactsById(conversation.meta.sender.id)"
      :state-inbox="stateInbox(conversation.inboxId)"
      :account-labels="accountLabelsValue"
      class="history-card"
    />
  </div>
  <p v-else class="empty-note">
    {{ t('CONTACTS_LAYOUT.SIDEBAR.HISTORY.EMPTY_STATE') }}
  </p>
</template>

<style scoped>
.tab-loading {
  display: flex;
  justify-content: center;
  padding: 24px;
}

.history-list {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.history-card {
  border-radius: 12px;
  border: 1px solid var(--border, #171520);
}
</style>
