<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { dynamicTime } from 'shared/helpers/timeHelper';

import ComposeConversation from 'dashboard/components-next/NewConversation/ComposeConversation.vue';
import VoiceCallButton from 'dashboard/components-next/Contacts/VoiceCallButton.vue';
import ContactLabels from 'dashboard/components-next/Contacts/ContactLabels/ContactLabels.vue';

const props = defineProps({
  selectedContact: {
    type: Object,
    default: () => ({}),
  },
  isUpdating: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['toggleBlock']);

const { t } = useI18n();
const route = useRoute();

const contactId = computed(() => route.params.contactId);

const selectedContactName = computed(() => props.selectedContact?.name);

const isContactBlocked = computed(() => props.selectedContact?.blocked);

const createdAt = computed(() => {
  const raw = props.selectedContact?.createdAt;
  return raw ? dynamicTime(raw) : '';
});

const lastActivityAt = computed(() => {
  const raw = props.selectedContact?.lastActivityAt;
  return raw ? dynamicTime(raw) : '';
});

const preferredGame = computed(() => {
  const platform =
    props.selectedContact?.customAttributes?.preferred_platform ||
    props.selectedContact?.customAttributes?.preferredPlatform;
  if (!platform) return '';
  return String(platform)
    .replace(/_/g, ' ')
    .replace(/\b\w/g, c => c.toUpperCase());
});

const lifecycleStage = computed(() => {
  const tier = props.selectedContact?.customAttributes?.loyalty_tier;
  if (tier) return String(tier);
  return t('CONTACTS_LAYOUT.PROFILE.ENGAGED');
});

const toggleBlock = () => {
  emit('toggleBlock', isContactBlocked.value);
};
</script>

<template>
  <div class="detail">
    <div v-if="selectedContact?.id" class="det-hero">
      <div class="det-hero-top">
        <div
          class="det-ava"
          :style="
            selectedContact.thumbnail
              ? { backgroundImage: `url(${selectedContact.thumbnail})` }
              : {}
          "
        >
          <span v-if="!selectedContact.thumbnail">{{
            (selectedContactName || '?').charAt(0).toUpperCase()
          }}</span>
        </div>
        <div class="det-id">
          <div class="dn display">{{ selectedContactName }}</div>
          <div v-if="selectedContact.identifier" class="duid mono">
            {{ selectedContact.identifier }}
          </div>
          <div class="dmeta">
            {{ t('CONTACTS_LAYOUT.DETAILS.CREATED_AT', { date: createdAt }) }}
            {{ t('CONTACTS_LAYOUT.META_SEPARATOR') }}
            {{
              t('CONTACTS_LAYOUT.DETAILS.LAST_ACTIVITY', {
                date: lastActivityAt,
              })
            }}
          </div>
          <div class="det-tags">
            <span class="tag engaged">{{ lifecycleStage }}</span>
            <span v-if="preferredGame" class="tag game">{{
              preferredGame
            }}</span>
            <ContactLabels :contact-id="selectedContact.id" />
          </div>
        </div>
        <div class="det-actions">
          <button
            type="button"
            class="btn danger"
            :disabled="isUpdating"
            @click="toggleBlock"
          >
            <svg
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="2"
            >
              <circle cx="12" cy="12" r="10" />
              <path d="M4.9 4.9l14.2 14.2" />
            </svg>
            {{
              !isContactBlocked
                ? $t('CONTACTS_LAYOUT.HEADER.BLOCK_CONTACT')
                : $t('CONTACTS_LAYOUT.HEADER.UNBLOCK_CONTACT')
            }}
          </button>
          <VoiceCallButton
            :phone="selectedContact?.phoneNumber"
            :contact-id="contactId"
            :label="$t('CONTACT_PANEL.CALL')"
            size="sm"
            class="patra-voice-btn"
          />
          <ComposeConversation :contact-id="contactId">
            <template #trigger>
              <button type="button" class="btn primary">
                <svg
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="2"
                >
                  <path
                    d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"
                  />
                </svg>
                {{ $t('CONTACTS_LAYOUT.HEADER.SEND_MESSAGE') }}
              </button>
            </template>
          </ComposeConversation>
        </div>
      </div>
    </div>
    <div class="det-body">
      <slot name="default" />
    </div>
  </div>
</template>

<style scoped>
:deep(.patra-voice-btn button) {
  font-size: 13px;
  font-weight: 500;
  padding: 9px 15px;
  border-radius: 10px;
  border: 1px solid var(--border);
  background: var(--surface-2);
  color: var(--text);
}

:deep(.det-tags .flex) {
  display: contents;
}
</style>
