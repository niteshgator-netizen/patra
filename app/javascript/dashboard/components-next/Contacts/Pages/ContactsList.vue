<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useRouter, useRoute } from 'vue-router';
import {
  DuplicateContactException,
  ExceptionWithMessage,
} from 'shared/helpers/CustomErrors';
import ContactsCard from 'dashboard/components-next/Contacts/ContactsCard/ContactsCard.vue';

const props = defineProps({
  contacts: { type: Array, required: true },
  selectedContactIds: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['toggleContact']);

const { t } = useI18n();
const store = useStore();
const router = useRouter();
const route = useRoute();

const uiFlags = useMapGetter('contacts/getUIFlags');
const isUpdating = computed(() => uiFlags.value.isUpdating);
const expandedCardId = ref(null);
const hoveredAvatarId = ref(null);

const selectedIdsSet = computed(() => new Set(props.selectedContactIds || []));

const updateContact = async updatedData => {
  try {
    await store.dispatch('contacts/update', updatedData);
    useAlert(t('CONTACTS_LAYOUT.CARD.EDIT_DETAILS_FORM.SUCCESS_MESSAGE'));
  } catch (error) {
    const i18nPrefix = 'CONTACTS_LAYOUT.CARD.EDIT_DETAILS_FORM.FORM';
    if (error instanceof DuplicateContactException) {
      if (error.data.includes('email')) {
        useAlert(t(`${i18nPrefix}.EMAIL_ADDRESS.DUPLICATE`));
      } else if (error.data.includes('phone_number')) {
        useAlert(t(`${i18nPrefix}.PHONE_NUMBER.DUPLICATE`));
      }
    } else if (error instanceof ExceptionWithMessage) {
      useAlert(error.data);
    } else {
      useAlert(t(`${i18nPrefix}.ERROR_MESSAGE`));
    }
  }
};

const onClickViewDetails = async id => {
  const routeTypes = {
    contacts_dashboard_segments_index: ['contacts_edit_segment', 'segmentId'],
    contacts_dashboard_labels_index: ['contacts_edit_label', 'label'],
  };
  const [name, paramKey] = routeTypes[route.name] || ['contacts_edit'];
  const params = {
    contactId: id,
    ...(paramKey && { [paramKey]: route.params[paramKey] }),
  };

  await router.push({ name, params, query: route.query });
};

const toggleExpanded = id => {
  expandedCardId.value = expandedCardId.value === id ? null : id;
};

const isSelected = id => selectedIdsSet.value.has(id);

const shouldShowSelection = id => {
  return hoveredAvatarId.value === id || isSelected(id);
};

const handleSelect = (id, value) => {
  emit('toggleContact', { id, value });
};

const handleAvatarHover = (id, isHovered) => {
  hoveredAvatarId.value = isHovered ? id : null;
};

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

const hasAiOffLabel = contact => {
  const labels = contact.labels || [];
  return labels.includes('ai-off');
};
</script>

<template>
  <div class="contacts-list">
    <div v-for="contact in contacts" :key="contact.id" class="contact-row-wrap">
      <div
        class="contact"
        :class="{ active: false, selected: isSelected(contact.id) }"
        @click="onClickViewDetails(contact.id)"
      >
        <div
          class="c-ava"
          :style="
            contact.thumbnail
              ? { backgroundImage: `url(${contact.thumbnail})` }
              : {}
          "
          @mouseenter="handleAvatarHover(contact.id, true)"
          @mouseleave="handleAvatarHover(contact.id, false)"
        >
          <span v-if="!contact.thumbnail">{{
            (contact.name || '?').charAt(0).toUpperCase()
          }}</span>
          <label
            v-if="shouldShowSelection(contact.id)"
            class="c-select"
            @click.stop
          >
            <input
              type="checkbox"
              :checked="isSelected(contact.id)"
              @change="handleSelect(contact.id, $event.target.checked)"
            />
          </label>
        </div>
        <div class="c-info">
          <div class="cn">{{ contact.name }}</div>
          <div class="cm">
            <span v-if="gameLabel(contact)">{{ gameLabel(contact) }}</span>
            <span v-if="isVip(contact)" class="c-tag vip">{{
              t('CONTACTS_LAYOUT.LIST.VIP')
            }}</span>
            <span v-if="hasAiOffLabel(contact)" class="c-tag aioff">{{
              t('CONTACTS_LAYOUT.FILTER_TABS.AI_OFF')
            }}</span>
          </div>
        </div>
        <button
          type="button"
          class="c-expand"
          @click.stop="toggleExpanded(contact.id)"
        >
          {{
            expandedCardId === contact.id
              ? t('CONTACTS_LAYOUT.LIST.EXPAND_OPEN')
              : t('CONTACTS_LAYOUT.LIST.EXPAND_CLOSED')
          }}
        </button>
        <span class="c-arrow">{{ t('CONTACTS_LAYOUT.LIST.ARROW') }}</span>
      </div>
      <div v-if="expandedCardId === contact.id" class="contact-expanded">
        <ContactsCard
          :id="contact.id"
          :name="contact.name"
          :email="contact.email"
          :thumbnail="contact.thumbnail"
          :phone-number="contact.phoneNumber"
          :additional-attributes="contact.additionalAttributes"
          :availability-status="contact.availabilityStatus"
          is-expanded
          :is-updating="isUpdating"
          :selectable="shouldShowSelection(contact.id)"
          :is-selected="isSelected(contact.id)"
          @toggle="toggleExpanded(contact.id)"
          @update-contact="updateContact"
          @show-contact="onClickViewDetails"
          @select="value => handleSelect(contact.id, value)"
          @avatar-hover="value => handleAvatarHover(contact.id, value)"
        />
      </div>
    </div>
  </div>
</template>

<style scoped>
.contact-row-wrap + .contact-row-wrap {
  margin-top: 2px;
}

.c-select {
  position: absolute;
  inset: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  background: rgba(0, 0, 0, 0.45);
  border-radius: 50%;
  cursor: pointer;
}

.c-expand {
  border: none;
  background: transparent;
  color: var(--text-4);
  cursor: pointer;
  font-size: 12px;
  padding: 0 4px;
}

.contact-expanded {
  margin: 4px 0 8px 11px;
  padding: 12px;
  border: 1px solid var(--border);
  border-radius: 12px;
  background: var(--surface-2);
}

.contact.selected {
  border-color: var(--patra);
}
</style>
