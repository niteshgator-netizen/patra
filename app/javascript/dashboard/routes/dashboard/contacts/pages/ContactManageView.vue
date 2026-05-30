<script setup>
import { onMounted, computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useRoute, useRouter } from 'vue-router';

import ContactsDetailsLayout from 'dashboard/components-next/Contacts/ContactsDetailsLayout.vue';
import PatraContactsCompactList from 'dashboard/components-next/Contacts/PatraContactsCompactList.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ContactDetails from 'dashboard/components-next/Contacts/Pages/ContactDetails.vue';
import ContactNotes from 'dashboard/components-next/Contacts/ContactsSidebar/ContactNotes.vue';
import ContactHistory from 'dashboard/components-next/Contacts/ContactsSidebar/ContactHistory.vue';
import ContactMerge from 'dashboard/components-next/Contacts/ContactsSidebar/ContactMerge.vue';
import ContactCustomAttributes from 'dashboard/components-next/Contacts/ContactsSidebar/ContactCustomAttributes.vue';

const store = useStore();
const route = useRoute();
const router = useRouter();

const contact = useMapGetter('contacts/getContactById');
const uiFlags = useMapGetter('contacts/getUIFlags');

const activeTab = ref('attributes');
const contactMergeRef = ref(null);
const spotlightRef = ref(null);

const isFetchingItem = computed(() => uiFlags.value.isFetchingItem);
const isMergingContact = computed(() => uiFlags.value.isMerging);
const isUpdatingContact = computed(() => uiFlags.value.isUpdating);

const selectedContact = computed(() => contact.value(route.params.contactId));

const showSpinner = computed(
  () => isFetchingItem.value || isMergingContact.value
);

const { t } = useI18n();

const CONTACT_TABS_OPTIONS = [
  { key: 'ATTRIBUTES', value: 'attributes' },
  { key: 'HISTORY', value: 'history' },
  { key: 'NOTES', value: 'notes' },
  { key: 'MERGE', value: 'merge' },
];

const goToContactsList = () => {
  if (window.history.state?.back || window.history.length > 1) {
    router.back();
  } else {
    router.push(`/app/accounts/${route.params.accountId}/contacts?page=1`);
  }
};

const fetchActiveContact = async () => {
  if (route.params.contactId) {
    await store.dispatch('contacts/show', { id: route.params.contactId });
    await store.dispatch(
      'contacts/fetchContactableInbox',
      route.params.contactId
    );
  }
};

const handleTabChange = tabValue => {
  activeTab.value = tabValue;
};

const fetchContactNotes = () => {
  const { contactId } = route.params;
  if (contactId) store.dispatch('contactNotes/get', { contactId });
};

const fetchContactConversations = () => {
  const { contactId } = route.params;
  if (contactId) store.dispatch('contactConversations/get', contactId);
};

const fetchAttributes = () => {
  store.dispatch('attributes/get');
};

const toggleContactBlock = async isBlocked => {
  const ALERT_MESSAGES = {
    success: {
      block: t('CONTACTS_LAYOUT.HEADER.ACTIONS.BLOCK_SUCCESS_MESSAGE'),
      unblock: t('CONTACTS_LAYOUT.HEADER.ACTIONS.UNBLOCK_SUCCESS_MESSAGE'),
    },
    error: {
      block: t('CONTACTS_LAYOUT.HEADER.ACTIONS.BLOCK_ERROR_MESSAGE'),
      unblock: t('CONTACTS_LAYOUT.HEADER.ACTIONS.UNBLOCK_ERROR_MESSAGE'),
    },
  };

  try {
    await store.dispatch(`contacts/update`, {
      ...selectedContact.value,
      blocked: !isBlocked,
    });
    useAlert(
      isBlocked ? ALERT_MESSAGES.success.unblock : ALERT_MESSAGES.success.block
    );
  } catch (error) {
    useAlert(
      isBlocked ? ALERT_MESSAGES.error.unblock : ALERT_MESSAGES.error.block
    );
  }
};

const onSpotlightMove = e => {
  const el = spotlightRef.value;
  if (!el) return;
  el.style.left = `${e.clientX}px`;
  el.style.top = `${e.clientY}px`;
  el.style.opacity = '1';
};

const onSpotlightLeave = () => {
  const el = spotlightRef.value;
  if (el) el.style.opacity = '0';
};

onMounted(() => {
  fetchActiveContact();
  fetchContactNotes();
  fetchContactConversations();
  fetchAttributes();
});
</script>

<template>
  <div
    class="contacts-wrap"
    @mousemove="onSpotlightMove"
    @mouseleave="onSpotlightLeave"
  >
    <div id="spotlight" ref="spotlightRef" />
    <div class="mesh" />
    <div class="contacts-app">
      <PatraContactsCompactList :active-contact-id="route.params.contactId" />

      <ContactsDetailsLayout
        :selected-contact="selectedContact"
        :is-updating="isUpdatingContact"
        @toggle-block="toggleContactBlock"
      >
        <div v-if="showSpinner" class="detail-loading">
          <Spinner />
        </div>
        <ContactDetails
          v-else-if="selectedContact"
          :selected-contact="selectedContact"
          @go-to-contacts-list="goToContactsList"
        >
          <template #tabs>
            <div class="card full">
              <div class="dtabs">
                <button
                  v-for="tab in CONTACT_TABS_OPTIONS"
                  :key="tab.value"
                  type="button"
                  class="dtab"
                  :class="{ active: activeTab === tab.value }"
                  @click="handleTabChange(tab.value)"
                >
                  {{ t(`CONTACTS_LAYOUT.SIDEBAR.TABS.${tab.key}`) }}
                </button>
              </div>
              <div
                class="tabpane"
                :class="{ active: activeTab === 'attributes' }"
              >
                <ContactCustomAttributes
                  v-if="activeTab === 'attributes'"
                  :selected-contact="selectedContact"
                />
              </div>
              <div
                class="tabpane"
                :class="{ active: activeTab === 'history' }"
              >
                <ContactHistory v-if="activeTab === 'history'" />
              </div>
              <div
                class="tabpane"
                :class="{ active: activeTab === 'notes' }"
              >
                <ContactNotes v-if="activeTab === 'notes'" />
              </div>
              <div
                class="tabpane"
                :class="{ active: activeTab === 'merge' }"
              >
                <ContactMerge
                  v-if="activeTab === 'merge'"
                  ref="contactMergeRef"
                  :selected-contact="selectedContact"
                  @go-to-contacts-list="goToContactsList"
                  @reset-tab="handleTabChange(CONTACT_TABS_OPTIONS[0].value)"
                />
              </div>
            </div>
          </template>
        </ContactDetails>
      </ContactsDetailsLayout>
    </div>
  </div>
</template>

<style lang="scss" scoped>
@import './contacts-patra.scss';
</style>
