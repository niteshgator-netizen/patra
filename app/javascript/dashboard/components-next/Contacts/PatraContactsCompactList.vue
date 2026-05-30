<script setup>
import { computed } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  activeContactId: {
    type: [String, Number],
    default: null,
  },
});

const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const contacts = useMapGetter('contacts/getContactsList');
const meta = useMapGetter('contacts/getMeta');

const totalItems = computed(() => meta.value?.count ?? contacts.value.length);
const activeId = computed(() =>
  Number(props.activeContactId || route.params.contactId)
);

const gameLabel = contact => {
  const platform =
    contact.customAttributes?.preferred_platform ||
    contact.customAttributes?.preferredPlatform;
  if (!platform) return '';
  return String(platform)
    .replace(/_/g, ' ')
    .replace(/\b\w/g, c => c.toUpperCase());
};

const isVip = contact =>
  String(contact.customAttributes?.loyalty_tier || '').toLowerCase() === 'vip';

const navigateToContact = async id => {
  if (Number(id) === activeId.value) return;
  const routeTypes = {
    contacts_edit_segment: ['contacts_edit_segment', 'segmentId'],
    contacts_edit_label: ['contacts_edit_label', 'label'],
  };
  const [name, paramKey] = routeTypes[route.name] || ['contacts_edit'];
  const params = {
    contactId: id,
    accountId: route.params.accountId,
    ...(paramKey && { [paramKey]: route.params[paramKey] }),
  };
  await router.push({ name, params, query: route.query });
};

const goToView = viewName => {
  router.push({
    name: viewName,
    params: { accountId: route.params.accountId },
    query: { page: 1 },
  });
};

const isActiveRoute = name => route.name === name;
</script>

<template>
  <div class="list">
    <div class="list-head">
      <div class="list-head-top">
        <div class="list-title display">
          {{ t('CONTACTS_LAYOUT.HEADER.TITLE') }}
          <span class="count">{{ totalItems }}</span>
        </div>
      </div>
      <div class="subnav">
        <button
          type="button"
          :class="{ active: isActiveRoute('contacts_dashboard_index') }"
          @click="goToView('contacts_dashboard_index')"
        >
          {{ t('CONTACTS_LAYOUT.FILTER_TABS.ALL') }}
        </button>
        <button
          type="button"
          :class="{ active: isActiveRoute('contacts_dashboard_active') }"
          @click="goToView('contacts_dashboard_active')"
        >
          {{ t('CONTACTS_LAYOUT.FILTER_TABS.ACTIVE') }}
        </button>
        <button
          type="button"
          :class="{ active: isActiveRoute('contacts_dashboard_labels_index') }"
          @click="
            router.push({
              name: 'contacts_dashboard_labels_index',
              params: {
                accountId: route.params.accountId,
                label: 'ai-off',
              },
              query: { page: 1 },
            })
          "
        >
          {{ t('CONTACTS_LAYOUT.FILTER_TABS.TAGGED') }}
          <span class="lbl-dot" />
          {{ t('CONTACTS_LAYOUT.FILTER_TABS.AI_OFF') }}
        </button>
      </div>
    </div>
    <div class="contacts">
      <div
        v-for="contact in contacts"
        :key="contact.id"
        class="contact"
        :class="{ active: contact.id === activeId }"
        @click="navigateToContact(contact.id)"
      >
        <div
          class="c-ava"
          :style="
            contact.thumbnail
              ? { backgroundImage: `url(${contact.thumbnail})` }
              : {}
          "
        >
          <span v-if="!contact.thumbnail">{{
            (contact.name || '?').charAt(0).toUpperCase()
          }}</span>
        </div>
        <div class="c-info">
          <div class="cn">{{ contact.name }}</div>
          <div class="cm">
            <span v-if="gameLabel(contact)">{{ gameLabel(contact) }}</span>
            <span v-if="isVip(contact)" class="c-tag vip">{{
              t('CONTACTS_LAYOUT.LIST.VIP')
            }}</span>
          </div>
        </div>
        <span class="c-arrow">{{ t('CONTACTS_LAYOUT.LIST.ARROW') }}</span>
      </div>
    </div>
  </div>
</template>
