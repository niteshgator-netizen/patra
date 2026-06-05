<script setup>
import { computed, watch, onMounted, ref } from 'vue';
import {
  useMapGetter,
  useFunctionGetter,
  useStore,
} from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

import AccordionItem from 'dashboard/components/Accordion/AccordionItem.vue';
import ContactConversations from './ContactConversations.vue';
import ConversationAction from './ConversationAction.vue';
import ConversationParticipant from './ConversationParticipant.vue';
import ContactInfo from './contact/ContactInfo.vue';
import ContactProfileStats from 'dashboard/components/widgets/ContactProfileStats.vue';
import ContactNotes from './contact/ContactNotes.vue';
import ConversationInfo from './ConversationInfo.vue';
import CustomAttributes from './customAttributes/CustomAttributes.vue';
import SharedFiles from './SharedFiles.vue';
import Draggable from 'vuedraggable';
import MacrosList from './Macros/List.vue';
import ShopifyOrdersList from 'dashboard/components/widgets/conversation/ShopifyOrdersList.vue';
import SidebarActionsHeader from 'dashboard/components-next/SidebarActionsHeader.vue';
import LinearIssuesList from 'dashboard/components/widgets/conversation/linear/IssuesList.vue';
import LinearSetupCTA from 'dashboard/components/widgets/conversation/linear/LinearSetupCTA.vue';
import PlayerProfileCard from 'dashboard/components/widgets/PlayerProfileCard.vue';
import GameQuickActionsPanel from 'dashboard/components/widgets/GameQuickActionsPanel.vue';
import PatraAiHandoffCard from 'dashboard/components/widgets/PatraAiHandoffCard.vue';
import SuggestedReplyCard from 'dashboard/components/widgets/SuggestedReplyCard.vue';

const props = defineProps({
  conversationId: {
    type: [Number, String],
    required: true,
  },
  inboxId: {
    type: Number,
    default: undefined,
  },
});

const {
  updateUISettings,
  isContactSidebarItemOpen,
  conversationSidebarItemsOrder,
  toggleSidebarUIState,
} = useUISettings();

const dragging = ref(false);
const conversationSidebarItems = ref([]);

const shopifyIntegration = useFunctionGetter(
  'integrations/getIntegration',
  'shopify'
);

const isShopifyFeatureEnabled = computed(
  () => shopifyIntegration.value.enabled
);

const { isCloudFeatureEnabled } = useAccount();

const isLinearFeatureEnabled = computed(() =>
  isCloudFeatureEnabled(FEATURE_FLAGS.LINEAR)
);

const linearIntegration = useFunctionGetter(
  'integrations/getIntegration',
  'linear'
);

const isLinearClientIdConfigured = computed(() => {
  return !!linearIntegration.value?.id;
});

const isLinearConnected = computed(
  () => linearIntegration.value?.enabled || false
);

const store = useStore();
const currentChat = useMapGetter('getSelectedChat');
const conversationId = computed(() => props.conversationId);
const conversationMetadataGetter = useMapGetter(
  'conversationMetadata/getConversationMetadata'
);
const currentConversationMetaData = computed(() =>
  conversationMetadataGetter.value(conversationId.value)
);
const conversationAdditionalAttributes = computed(
  () => currentConversationMetaData.value.additional_attributes || {}
);

const channelType = computed(() => currentChat.value.meta?.channel);

const contactGetter = useMapGetter('contacts/getContact');
const contactId = computed(() => currentChat.value.meta?.sender?.id);
const contact = computed(() => contactGetter.value(contactId.value));
const contactAdditionalAttributes = computed(
  () => contact.value.additional_attributes || {}
);

const getContactDetails = () => {
  if (contactId.value) {
    store.dispatch('contacts/show', { id: contactId.value });
  }
};

watch(contactId, (newContactId, prevContactId) => {
  if (newContactId && newContactId !== prevContactId) {
    getContactDetails();
  }
});

const syncConversationSidebarItemsFromSettings = () => {
  if (dragging.value) return;
  conversationSidebarItems.value = conversationSidebarItemsOrder.value.map(
    item => ({ ...item })
  );
};

watch(conversationSidebarItemsOrder, syncConversationSidebarItemsFromSettings, {
  deep: true,
  immediate: true,
});

const onDragEnd = () => {
  dragging.value = false;
  updateUISettings({
    conversation_sidebar_items_order: conversationSidebarItems.value,
  });
};

const closeContactPanel = () => {
  updateUISettings({
    is_contact_sidebar_open: false,
    is_copilot_panel_open: false,
  });
};

onMounted(() => {
  getContactDetails();
  store.dispatch('attributes/get', 0);
  // Load integrations to ensure linear integration state is available
  store.dispatch('integrations/get', 'linear');
});
</script>

<template>
  <div class="conv-sidebar-patra contact-panel-v6 w-full flex flex-col min-h-0">
    <SidebarActionsHeader
      class="ctx-sidebar-header shrink-0"
      :title="$t('CONVERSATION.SIDEBAR.CONTACT')"
      @close="closeContactPanel"
    />
    <div class="ctx-body flex-1">
      <div class="profile">
        <ContactInfo :contact="contact" :channel-type="channelType" />
      </div>
      <ContactProfileStats :contact="contact" />
      <div class="sidebar-accordions">
        <Draggable
          :list="conversationSidebarItems"
          animation="200"
          ghost-class="ghost"
          handle=".drag-handle"
          item-key="name"
          class="flex flex-col"
          @start="dragging = true"
          @end="onDragEnd"
        >
          <template #item="{ element }">
            <div v-if="element.name === 'conversation_actions'">
              <AccordionItem
                patra
                :title="
                  $t('CONVERSATION_SIDEBAR.ACCORDION.CONVERSATION_ACTIONS')
                "
                :is-open="isContactSidebarItemOpen('is_conv_actions_open')"
                @toggle="() => toggleSidebarUIState('is_conv_actions_open')"
              >
                <ConversationAction
                  :conversation-id="conversationId"
                  :inbox-id="inboxId"
                />
              </AccordionItem>
            </div>
            <div v-else-if="element.name === 'conversation_participants'">
              <div class="ctx-section">
                <div class="ctx-label">
                  {{ $t('CONVERSATION_PARTICIPANTS.SIDEBAR_TITLE') }}
                </div>
                <ConversationParticipant
                  :conversation-id="conversationId"
                  :inbox-id="inboxId"
                />
              </div>
            </div>
            <div v-else-if="element.name === 'conversation_info'">
              <AccordionItem
                patra
                :title="$t('CONVERSATION_SIDEBAR.ACCORDION.CONVERSATION_INFO')"
                :is-open="isContactSidebarItemOpen('is_conv_details_open')"
                compact
                @toggle="() => toggleSidebarUIState('is_conv_details_open')"
              >
                <ConversationInfo
                  :conversation-attributes="conversationAdditionalAttributes"
                  :contact-attributes="contactAdditionalAttributes"
                />
              </AccordionItem>
            </div>
            <div v-else-if="element.name === 'contact_attributes'">
              <AccordionItem
                patra
                :title="$t('CONVERSATION_SIDEBAR.ACCORDION.CONTACT_ATTRIBUTES')"
                :is-open="
                  isContactSidebarItemOpen('is_contact_attributes_open')
                "
                compact
                @toggle="
                  () => toggleSidebarUIState('is_contact_attributes_open')
                "
              >
                <CustomAttributes
                  attribute-type="contact_attribute"
                  attribute-from="conversation_contact_panel"
                  :contact-id="contact.id"
                  :empty-state-message="
                    $t('CONVERSATION_CUSTOM_ATTRIBUTES.NO_RECORDS_FOUND')
                  "
                />
              </AccordionItem>
            </div>
            <div v-else-if="element.name === 'player_profile'">
              <PatraAiHandoffCard :conversation-id="conversationId" />
              <SuggestedReplyCard :conversation-id="conversationId" />
              <PlayerProfileCard
                :contact="contact"
                :conversation-id="conversationId"
              />
              <div class="ctx-section ops-panel">
                <div class="ctx-label">
                  {{ $t('GAMES.QUICK_ACTIONS.TITLE') }}
                  <span class="ops-hint">{{
                    $t('GAMES.QUICK_ACTIONS.LIVE_HINT')
                  }}</span>
                </div>
                <GameQuickActionsPanel />
              </div>
            </div>
            <div v-else-if="element.name === 'previous_conversation'">
              <AccordionItem
                v-if="contact.id"
                patra
                :title="
                  $t('CONVERSATION_SIDEBAR.ACCORDION.PREVIOUS_CONVERSATION')
                "
                :is-open="isContactSidebarItemOpen('is_previous_conv_open')"
                compact
                @toggle="() => toggleSidebarUIState('is_previous_conv_open')"
              >
                <ContactConversations
                  :contact-id="contact.id"
                  :conversation-id="conversationId"
                />
              </AccordionItem>
            </div>
            <woot-feature-toggle
              v-else-if="element.name === 'macros'"
              feature-key="macros"
            >
              <AccordionItem
                patra
                :title="$t('CONVERSATION_SIDEBAR.ACCORDION.MACROS')"
                :is-open="isContactSidebarItemOpen('is_macro_open')"
                compact
                @toggle="() => toggleSidebarUIState('is_macro_open')"
              >
                <MacrosList :conversation-id="conversationId" />
              </AccordionItem>
            </woot-feature-toggle>
            <div
              v-else-if="
                element.name === 'linear_issues' &&
                isLinearFeatureEnabled &&
                isLinearClientIdConfigured
              "
            >
              <AccordionItem
                patra
                :title="$t('CONVERSATION_SIDEBAR.ACCORDION.LINEAR_ISSUES')"
                :is-open="isContactSidebarItemOpen('is_linear_issues_open')"
                compact
                @toggle="() => toggleSidebarUIState('is_linear_issues_open')"
              >
                <LinearSetupCTA v-if="!isLinearConnected" />
                <LinearIssuesList v-else :conversation-id="conversationId" />
              </AccordionItem>
            </div>
            <div
              v-else-if="
                element.name === 'shopify_orders' && isShopifyFeatureEnabled
              "
            >
              <AccordionItem
                patra
                :title="$t('CONVERSATION_SIDEBAR.ACCORDION.SHOPIFY_ORDERS')"
                :is-open="isContactSidebarItemOpen('is_shopify_orders_open')"
                compact
                @toggle="() => toggleSidebarUIState('is_shopify_orders_open')"
              >
                <ShopifyOrdersList :contact-id="contactId" />
              </AccordionItem>
            </div>
            <div v-else-if="element.name === 'contact_notes'">
              <AccordionItem
                patra
                :title="$t('CONVERSATION_SIDEBAR.ACCORDION.CONTACT_NOTES')"
                :is-open="isContactSidebarItemOpen('is_contact_notes_open')"
                compact
                @toggle="() => toggleSidebarUIState('is_contact_notes_open')"
              >
                <ContactNotes :contact-id="contactId" />
              </AccordionItem>
            </div>
            <div v-else-if="element.name === 'shared_files'">
              <AccordionItem
                patra
                :title="$t('CONVERSATION_SIDEBAR.ACCORDION.SHARED_FILES')"
                :is-open="isContactSidebarItemOpen('is_shared_files_open')"
                compact
                @toggle="() => toggleSidebarUIState('is_shared_files_open')"
              >
                <SharedFiles />
              </AccordionItem>
            </div>
          </template>
        </Draggable>
      </div>
    </div>
  </div>
</template>

<style lang="scss" scoped>
@import 'dashboard/components/widgets/conversation/conversation-sidebar-patra.scss';

/* ── v6 right sidebar ── */
.contact-panel-v6,
.conversation-sidebar,
.contact-panel {
  background: var(--surface, #0c0b12);
  border-left: 1px solid var(--border, #171520);
  display: flex;
  flex-direction: column;
  overflow-y: auto;
  height: 100%;
}

/* Tabs */
.contact-panel-v6 :deep(.tabs-pane),
.contact-panel-v6 :deep(.tabs) {
  border-bottom: 1px solid var(--border, #171520);
  background: var(--surface, #0c0b12);
  padding: 0 12px;
}
.contact-panel-v6 :deep(.tabs-title a),
.contact-panel-v6 :deep(.tabs-title button) {
  font-size: 13px;
  font-weight: 500;
  color: var(--text-2, #a8a6b6);
  padding: 10px 12px;
  border-bottom: 2px solid transparent;
  transition: all 0.2s;
}
.contact-panel-v6 :deep(.tabs-title.is-active a),
.contact-panel-v6 :deep(.tabs-title.is-active button) {
  color: var(--patra-3, #a78bfa);
  border-bottom-color: var(--patra, #6e56cf);
}

/* Section labels */
.contact-panel-v6 :deep(.conv-details--label),
.contact-panel-v6 :deep(.section-label) {
  font-size: 10px;
  font-weight: 700;
  letter-spacing: 0.08em;
  text-transform: uppercase;
  color: var(--text-4, #54515e);
  padding: 14px 16px 6px;
}

/* Accordion headers */
.contact-panel-v6 :deep(.accordion-head),
.contact-panel-v6 :deep(.conv-details-item) {
  padding: 10px 16px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  cursor: pointer;
  font-size: 13px;
  font-weight: 600;
  color: var(--text, #ededf2);
  border-top: 1px solid var(--border, #171520);
  transition: background 0.2s;
  font-family: 'Space Grotesk', sans-serif;
}
.contact-panel-v6 :deep(.accordion-head:hover) {
  background: var(--surface-2, #131119);
}

/* Field rows */
.contact-panel-v6 :deep(.conv-details--item),
.contact-panel-v6 :deep(.field-row) {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 5px 16px;
  font-size: 12.5px;
}
.contact-panel-v6 :deep(.conv-details--item .title),
.contact-panel-v6 :deep(.field-key) {
  color: var(--text-3, #75727f);
  font-weight: 500;
}
.contact-panel-v6 :deep(.conv-details--item .value),
.contact-panel-v6 :deep(.field-val) {
  color: var(--text, #ededf2);
  font-weight: 500;
  text-align: right;
}

/* Stats grid */
.pat-stat-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 8px;
  padding: 10px 16px;
}
.pat-stat-cell {
  background: var(--surface-2, #131119);
  border: 1px solid var(--border, #171520);
  border-radius: 10px;
  padding: 10px 12px;
  display: flex;
  flex-direction: column;
  gap: 3px;
}
.pat-stat-cell .n {
  font-size: 16px;
  font-weight: 700;
  color: var(--text, #ededf2);
  font-family: 'JetBrains Mono', monospace;
}
.pat-stat-cell .n.g {
  color: var(--green, #3fb950);
}
.pat-stat-cell .n.p {
  color: var(--patra-3, #a78bfa);
}
.pat-stat-cell .l {
  font-size: 10px;
  color: var(--text-3, #75727f);
  font-weight: 500;
}

/* Macro rows */
.contact-panel-v6 :deep(.macro-row) {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 7px 16px;
  font-size: 12.5px;
  color: var(--text-2, #a8a6b6);
  border-bottom: 1px solid var(--border, #171520);
  transition: background 0.2s;
}
.contact-panel-v6 :deep(.macro-row:hover) {
  background: var(--surface-2, #131119);
  color: var(--text, #ededf2);
}

/* Bridge: spec → existing Patra DOM */
.contact-panel-v6 :deep(.sidebar-accordions .acc) {
  border-radius: 0;
  background: transparent;
  margin-bottom: 0;
  border: none;
  border-top: 1px solid var(--border, #171520);
}

.contact-panel-v6 :deep(.acc-h) {
  padding: 10px 16px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  cursor: pointer;
  font-size: 13px;
  font-weight: 600;
  color: var(--text, #ededf2);
  border-top: none;
  transition: background 0.2s;
  font-family: 'Space Grotesk', sans-serif;
}

.contact-panel-v6 :deep(.acc-h:hover) {
  background: var(--surface-2, #131119);
}

.contact-panel-v6 :deep(.ctx-label),
.contact-panel-v6 :deep(.sub-label) {
  font-size: 10px;
  font-weight: 700;
  letter-spacing: 0.08em;
  text-transform: uppercase;
  color: var(--text-4, #54515e);
  padding: 14px 16px 6px;
  margin-bottom: 0;
  font-family: inherit;
}

.contact-panel-v6 :deep(.field) {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 5px 16px;
  font-size: 12.5px;
  border-bottom: none;
}

.contact-panel-v6 :deep(.field .k) {
  color: var(--text-3, #75727f);
  font-weight: 500;
}

.contact-panel-v6 :deep(.field .v) {
  color: var(--text, #ededf2);
  font-weight: 500;
  text-align: right;
}

.contact-panel-v6 :deep(.stat-row) {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 8px;
  padding: 10px 16px;
  margin-bottom: 0;
}

.contact-panel-v6 :deep(.stat) {
  background: var(--surface-2, #131119);
  border: 1px solid var(--border, #171520);
  border-radius: 10px;
  padding: 10px 12px;
  display: flex;
  flex-direction: column;
  gap: 3px;
  cursor: default;
}

.contact-panel-v6 :deep(.stat::after) {
  display: none;
}

.contact-panel-v6 :deep(.stat.js-spot:hover) {
  border-color: var(--border, #171520);
  transform: none;
  box-shadow: none;
}

.contact-panel-v6 :deep(.stat .n) {
  font-size: 16px;
  font-weight: 700;
  color: var(--text, #ededf2);
  font-family: 'JetBrains Mono', monospace;
  line-height: 1.2;
}

.contact-panel-v6 :deep(.stat .n.g) {
  color: var(--green, #3fb950);
  background: none;
  -webkit-text-fill-color: var(--green, #3fb950);
}

.contact-panel-v6 :deep(.stat .n.p) {
  color: var(--patra-3, #a78bfa);
  background: none;
  -webkit-text-fill-color: var(--patra-3, #a78bfa);
}

.contact-panel-v6 :deep(.stat .n.sm) {
  font-size: 16px;
}

.contact-panel-v6 :deep(.stat .l) {
  font-size: 10px;
  color: var(--text-3, #75727f);
  font-weight: 500;
  margin-top: 0;
}
</style>
