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
const sidebarTab = ref('details');
const copilotQuery = ref('');

const askCopilot = () => {
  if (!copilotQuery.value.trim()) return;
  // Future: send to copilot API
  copilotQuery.value = '';
};

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
const allAttachments = useMapGetter('getSelectedChatAttachments');
const attachmentCount = computed(() => allAttachments.value.length);
const recentAttachments = computed(() => allAttachments.value.slice(-6));
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
      <div class="patra-sidebar-tabs">
        <button
          class="patra-sidebar-tab"
          :class="{ active: sidebarTab === 'details' }"
          @click="sidebarTab = 'details'"
        >
          Details
        </button>
        <button
          class="patra-sidebar-tab"
          :class="{ active: sidebarTab === 'copilot' }"
          @click="sidebarTab = 'copilot'"
        >
          Copilot
        </button>
      </div>
      <div v-show="sidebarTab === 'details'">
        <ContactProfileStats :contact="contact" />
        <div
          v-if="
            contact?.custom_attributes &&
            Object.keys(contact.custom_attributes).length
          "
          class="patra-contact-attrs"
        >
          <div class="card-t display">
            <span class="dot" />
            Contact Attributes
          </div>
          <div
            v-for="(val, key) in contact.custom_attributes"
            :key="key"
            class="patra-attr-row"
          >
            <span class="patra-attr-key">{{ key.replace(/_/g, ' ') }}</span>
            <span class="patra-attr-val">{{ val }}</span>
          </div>
        </div>
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
              <div
                v-if="attachmentCount > 0"
                class="patra-media-section"
              >
                <div class="card-t display">
                  <span class="dot" />
                  Attachments
                  <span class="patra-media-count"
                    >MEDIA · {{ attachmentCount }}</span
                  >
                  <a class="patra-media-viewall">View all →</a>
                </div>
                <div class="patra-media-grid">
                  <div
                    v-for="att in recentAttachments"
                    :key="att.id"
                    class="patra-media-thumb"
                  >
                    <img
                      v-if="att.thumb_url || att.data_url"
                      :src="att.thumb_url || att.data_url"
                      :alt="att.file_name || 'Attachment'"
                      loading="lazy"
                    />
                    <span v-else class="patra-media-file">📄</span>
                  </div>
                  <div
                    v-if="attachmentCount > 6"
                    class="patra-media-more"
                  >
                    +{{ attachmentCount - 6 }}
                  </div>
                </div>
              </div>
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
      <div v-show="sidebarTab === 'copilot'" class="patra-copilot-tab">
        <PatraAiHandoffCard :conversation-id="conversationId" />
        <SuggestedReplyCard :conversation-id="conversationId" />
        <div class="patra-confidence-section">
          <div class="patra-conf-title">Confidence scores</div>
          <div
            v-if="currentChat?.additional_attributes?.cashout_sla_policy"
            class="patra-conf-row"
          >
            <span class="patra-conf-label">Cashout SLA policy</span>
            <div class="patra-conf-bar">
              <div class="patra-conf-fill" style="width: 98%" />
            </div>
            <span class="patra-conf-pct">98%</span>
          </div>
          <div
            v-if="currentChat?.additional_attributes?.last_intent_confidence"
            class="patra-conf-row"
          >
            <span class="patra-conf-label">Intent match</span>
            <div class="patra-conf-bar">
              <div
                class="patra-conf-fill"
                :style="{
                  width:
                    Math.round(
                      (currentChat?.additional_attributes
                        ?.last_intent_confidence || 0) * 100
                    ) + '%',
                }"
              />
            </div>
            <span class="patra-conf-pct">{{
              Math.round(
                (currentChat?.additional_attributes?.last_intent_confidence ||
                  0) * 100
              )
            }}%</span>
          </div>
          <div class="patra-conf-row">
            <span class="patra-conf-label">RAG knowledge base</span>
            <div class="patra-conf-bar">
              <div class="patra-conf-fill" style="width: 91%" />
            </div>
            <span class="patra-conf-pct">91%</span>
          </div>
        </div>
        <!-- Copilot input -->
        <div class="patra-copilot-input">
          <input
            v-model="copilotQuery"
            type="text"
            placeholder="Ask Patra AI anything…"
            class="patra-cop-input"
            @keydown.enter="askCopilot"
          />
        </div>
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

.patra-contact-attrs {
  padding: 0 0 8px;
  border-bottom: 1px solid var(--border, #171520);
}

.patra-contact-attrs .card-t {
  font-family: 'Space Grotesk', sans-serif;
  font-weight: 600;
  font-size: 13px;
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 10px 16px;
  color: var(--text, #ededf2);
}

.patra-contact-attrs .dot {
  width: 7px;
  height: 7px;
  border-radius: 50%;
  background: var(--patra-2, #8b5cf6);
}

.patra-attr-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 5px 16px;
  font-size: 12.5px;
}

.patra-attr-key {
  color: var(--text-3, #75727f);
  font-weight: 500;
  text-transform: capitalize;
}

.patra-attr-val {
  color: var(--text, #ededf2);
  font-weight: 500;
  text-align: right;
  max-width: 55%;
  overflow: hidden;
  text-overflow: ellipsis;
}

.patra-media-section {
  padding: 8px 12px;
  border-top: 1px solid var(--border, #171520);
}

.patra-media-section .card-t {
  font-family: 'Space Grotesk', sans-serif;
  font-weight: 600;
  font-size: 13px;
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 10px 4px 6px;
  color: var(--text, #ededf2);
}

.patra-media-section .dot {
  width: 7px;
  height: 7px;
  border-radius: 50%;
  background: var(--patra-2, #8b5cf6);
}

.patra-media-count {
  margin-left: auto;
  font-size: 10px;
  color: #75727f;
  text-transform: uppercase;
}

.patra-media-viewall {
  font-size: 10px;
  color: #8b5cf6;
  cursor: pointer;
  margin-left: 8px;
}

.patra-media-grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 4px;
  margin-top: 6px;
}

.patra-media-thumb {
  width: 100%;
  aspect-ratio: 1;
  border-radius: 6px;
  overflow: hidden;
  background: rgba(110, 86, 207, 0.06);
}

.patra-media-thumb img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.patra-media-file {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 100%;
  height: 100%;
  font-size: 18px;
}

.patra-media-more {
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 12px;
  color: #8b5cf6;
  font-weight: 600;
  background: rgba(110, 86, 207, 0.08);
  border-radius: 6px;
  aspect-ratio: 1;
}

.patra-sidebar-tabs {
  display: flex;
  gap: 0;
  border-bottom: 1px solid rgba(110, 86, 207, 0.15);
  margin: 0 12px 8px;
  padding: 0;
}

.patra-sidebar-tab {
  flex: 1;
  padding: 8px 0;
  font-size: 12px;
  font-weight: 600;
  background: none;
  border: none;
  border-bottom: 2px solid transparent;
  color: #75727f;
  cursor: pointer;
  text-align: center;
}

.patra-sidebar-tab.active {
  color: #a78bfa;
  border-bottom-color: #6e56cf;
}

.patra-copilot-tab {
  padding: 0 4px;
}

.patra-confidence-section {
  margin: 8px 12px;
}

.patra-conf-title {
  font-size: 10px;
  font-weight: 600;
  color: #75727f;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  margin-bottom: 8px;
}

.patra-conf-row {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-bottom: 6px;
}

.patra-conf-label {
  font-size: 11px;
  color: #ededf2;
  flex: 1;
}

.patra-conf-bar {
  flex: 1;
  height: 6px;
  border-radius: 3px;
  background: rgba(110, 86, 207, 0.12);
  overflow: hidden;
}

.patra-conf-fill {
  height: 100%;
  border-radius: 3px;
  background: linear-gradient(90deg, #6e56cf, #8b5cf6);
}

.patra-conf-pct {
  font-size: 11px;
  font-weight: 600;
  color: #a78bfa;
  min-width: 30px;
  text-align: right;
}

.patra-copilot-input {
  padding: 8px 12px;
  border-top: 1px solid rgba(110, 86, 207, 0.12);
}

.patra-cop-input {
  width: 100%;
  padding: 8px 12px;
  border-radius: 10px;
  background: #131119;
  border: 1px solid rgba(110, 86, 207, 0.2);
  color: #ededf2;
  font-size: 12px;
  outline: none;
}

.patra-cop-input:focus {
  border-color: #6e56cf;
  box-shadow: 0 0 0 3px rgba(110, 86, 207, 0.11);
}

.patra-cop-input::placeholder {
  color: #54515e;
}
</style>
