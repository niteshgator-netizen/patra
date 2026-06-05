<script setup>
import { computed, ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useClipboard } from '@vueuse/core';

import ContactsForm from 'dashboard/components-next/Contacts/ContactsForm/ContactsForm.vue';
import ConfirmContactDeleteDialog from 'dashboard/components-next/Contacts/ContactsForm/ConfirmContactDeleteDialog.vue';
import Policy from 'dashboard/components/policy.vue';
import GameQuickActionsPanel from 'dashboard/components/widgets/GameQuickActionsPanel.vue';

const props = defineProps({
  selectedContact: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['goToContactsList']);

const { t } = useI18n();
const store = useStore();
const { copy, copied } = useClipboard();

const confirmDeleteContactDialogRef = ref(null);
const contactsFormRef = ref(null);
const contactData = ref({});

const uiFlags = useMapGetter('contacts/getUIFlags');
const isUpdating = computed(() => uiFlags.value.isUpdating);
const isFormInvalid = computed(() => contactsFormRef.value?.isFormInvalid);

const stats = computed(() => props.selectedContact?.profile_stats || {});

const getInitialContactData = () => {
  if (!props.selectedContact) return {};
  return { ...props.selectedContact };
};

onMounted(() => {
  Object.assign(contactData.value, getInitialContactData());

  document.querySelectorAll('.pat-sg.js-spot').forEach(el => {
    el.addEventListener('mousemove', e => {
      const r = el.getBoundingClientRect();
      el.style.setProperty('--mx', `${e.clientX - r.left}px`);
      el.style.setProperty('--my', `${e.clientY - r.top}px`);
    });
  });
});

const formatMoney = val => {
  const n = Number.parseFloat(val);
  if (Number.isNaN(n)) return '$0';
  return new Intl.NumberFormat(undefined, {
    style: 'currency',
    currency: 'USD',
    maximumFractionDigits: 0,
  }).format(n);
};

const humanizeGame = slug => {
  if (!slug) return '—';
  return String(slug)
    .replace(/_/g, ' ')
    .replace(/\b\w/g, c => c.toUpperCase());
};

const humanizePayment = method => {
  if (!method || method === 'Unknown') return '—';
  return String(method)
    .replace(/_/g, ' ')
    .replace(/\b\w/g, c => c.toUpperCase());
};

const gameCredentials = computed(() => {
  const attrs = props.selectedContact?.customAttributes || {};
  const creds = [];
  Object.entries(attrs).forEach(([key, value]) => {
    if (!key.startsWith('game_username_') || !value) return;
    const game = key.replace(/^game_username_/, '');
    const password = attrs[`game_password_${game}`];
    if (password) creds.push({ game, username: value, password });
  });
  return creds;
});

const vaultCursorId = computed(
  () => props.selectedContact?.customAttributes?.vault_cursor_id || '—'
);

const lifecycleStage = computed(() => {
  const tier = props.selectedContact?.customAttributes?.loyalty_tier;
  return tier ? String(tier) : t('CONTACTS_LAYOUT.PROFILE.ENGAGED');
});

const preferredGame = computed(() =>
  humanizeGame(
    props.selectedContact?.customAttributes?.preferred_platform ||
      stats.value.last_game
  )
);

const countryDisplay = computed(() => {
  const attrs = props.selectedContact?.additionalAttributes || {};
  const code = attrs.countryCode || attrs.country;
  return code ? `🇺🇸 +${String(code).replace(/\D/g, '')}` : '—';
});

const handleFormUpdate = updatedData => {
  Object.assign(contactData.value, updatedData);
};

const updateContact = async () => {
  try {
    const { customAttributes, ...basicContactData } = contactData.value;
    await store.dispatch('contacts/update', basicContactData);
    await store.dispatch(
      'contacts/fetchContactableInbox',
      props.selectedContact.id
    );
    useAlert(t('CONTACTS_LAYOUT.CARD.EDIT_DETAILS_FORM.SUCCESS_MESSAGE'));
  } catch (error) {
    useAlert(t('CONTACTS_LAYOUT.CARD.EDIT_DETAILS_FORM.ERROR_MESSAGE'));
  }
};

const openConfirmDeleteContactDialog = () => {
  confirmDeleteContactDialogRef.value?.dialogRef.open();
};

const copyValue = async value => {
  await copy(String(value));
  if (copied.value) {
    useAlert(t('CONTACT_PANEL.COPY_SUCCESSFUL'));
  }
};

const maskPassword = password => {
  const tail = String(password).slice(-3);
  return `•••••${tail}`;
};

const gameEmoji = game =>
  ({
    game_vault: '🎰',
    juwa: '🐉',
    ultra_panda: '🐼',
  })[game] || '🎮';

const openMerge = () => {
  const contactId = props.selectedContact?.id;
  if (contactId) {
    window.location.href = `/app/accounts/2/contacts/${contactId}`;
  }
};

const sendMessage = () => {
  const contactId = props.selectedContact?.id;
  if (contactId) {
    window.open(
      `/app/accounts/2/conversations?contactId=${contactId}`,
      '_self'
    );
  }
};
</script>

<template>
  <div class="contact-details">
    <div class="patra-contact-actions">
      <button type="button" class="patra-merge-btn" @click="openMerge">
        Merge
      </button>
      <button type="button" class="patra-send-msg-btn" @click="sendMessage">
        Send message
      </button>
    </div>
    <div class="card full">
      <div class="card-t display">
        <span class="dot" />
        {{ t('PATRA.PROFILE.STATS') }}
      </div>
      <div class="pat-stats-grid">
        <div class="pat-sg js-spot">
          <div class="pat-sg-n pat-sg-purple">
            {{ stats.conversation_count ?? 0 }}
          </div>
          <div class="pat-sg-l">{{ t('PATRA.PROFILE.CONVERSATIONS') }}</div>
        </div>
        <div class="pat-sg js-spot">
          <div class="pat-sg-n pat-sg-green">
            {{ stats.deposits?.count ?? 0 }}
            {{ t('CONTACTS_LAYOUT.META_SEPARATOR') }}
            {{ formatMoney(stats.deposits?.total) }}
          </div>
          <div class="pat-sg-l">{{ t('PATRA.PROFILE.DEPOSITS') }}</div>
        </div>
        <div class="pat-sg js-spot">
          <div class="pat-sg-n">
            {{ stats.cashouts?.count ?? 0 }}
            {{ t('CONTACTS_LAYOUT.META_SEPARATOR') }}
            {{ formatMoney(stats.cashouts?.total) }}
          </div>
          <div class="pat-sg-l">{{ t('PATRA.PROFILE.CASHOUTS') }}</div>
        </div>
        <div class="pat-sg js-spot">
          <div class="pat-sg-n">
            {{ formatMoney(stats.deposits?.last_amount || stats.last_deposit) }}
          </div>
          <div class="pat-sg-l">
            {{ t('CONTACTS_LAYOUT.PROFILE.LAST_DEPOSIT') }}
          </div>
        </div>
        <div class="pat-sg js-spot">
          <div class="pat-sg-n pat-sg-sm">
            {{ humanizePayment(stats.preferred_payment) }}
          </div>
          <div class="pat-sg-l">{{ t('PATRA.PROFILE.PREFERRED_PAYMENT') }}</div>
        </div>
        <div class="pat-sg js-spot">
          <div class="pat-sg-n pat-sg-sm">
            {{ humanizeGame(stats.last_game) }}
          </div>
          <div class="pat-sg-l">{{ t('PATRA.PROFILE.LAST_GAME') }}</div>
        </div>
      </div>
    </div>

    <div class="card">
      <div class="card-t display">
        <span class="dot" />
        {{ t('CONTACTS_LAYOUT.PLAYER_VAULT.TITLE') }}
        <span v-if="gameCredentials.length" class="more">
          {{
            t('CONTACTS_LAYOUT.PLAYER_VAULT.GAMES_COUNT', {
              count: gameCredentials.length,
            })
          }}
        </span>
      </div>
      <template v-if="gameCredentials.length">
        <div
          v-for="cred in gameCredentials"
          :key="cred.game"
          class="vault-card"
        >
          <div class="vault-game">
            <span class="vg-ic">{{ gameEmoji(cred.game) }}</span>
            {{ humanizeGame(cred.game) }}
            <span class="pat-vg-stat">{{
              t('CONTACTS_LAYOUT.PLAYER_VAULT.ACTIVE')
            }}</span>
          </div>
          <div class="vault-cred">
            <span class="vc-k">{{
              t('CONTACTS_LAYOUT.PLAYER_VAULT.USER')
            }}</span>
            <span class="vc-v">{{ cred.username }}</span>
            <button
              type="button"
              class="vc-copy"
              @click="copyValue(cred.username)"
            >
              {{ t('CONTACTS_LAYOUT.PLAYER_VAULT.COPY') }}
            </button>
          </div>
          <div class="vault-cred">
            <span class="vc-k">{{
              t('CONTACTS_LAYOUT.PLAYER_VAULT.PASS')
            }}</span>
            <span class="vc-v">{{ maskPassword(cred.password) }}</span>
            <button
              type="button"
              class="vc-copy"
              @click="copyValue(cred.password)"
            >
              {{ t('CONTACTS_LAYOUT.PLAYER_VAULT.COPY') }}
            </button>
          </div>
        </div>
      </template>
      <div v-else class="empty-note">
        {{ t('CONTACTS_LAYOUT.PLAYER_VAULT.EMPTY') }}
      </div>
    </div>

    <div class="card">
      <div class="card-t display">
        <span class="dot" />
        {{ t('CONTACTS_LAYOUT.PROFILE.TITLE') }}
      </div>
      <div class="field">
        <span class="k">{{ t('CONTACTS_LAYOUT.PROFILE.LIFECYCLE') }}</span>
        <span class="v">
          <span class="tag engaged">{{ lifecycleStage }}</span>
        </span>
      </div>
      <div class="field">
        <span class="k">{{ t('CONTACTS_LAYOUT.PROFILE.LOYALTY_TIER') }}</span>
        <span class="v">{{
          selectedContact?.customAttributes?.loyalty_tier || 'new'
        }}</span>
      </div>
      <div class="field">
        <span class="k">{{
          t('CONTACTS_LAYOUT.PROFILE.PREFERRED_PLATFORM')
        }}</span>
        <span class="v">{{ preferredGame }}</span>
      </div>
      <div class="field">
        <span class="k">{{ t('CONTACTS_LAYOUT.PROFILE.TOTAL_DEPOSITS') }}</span>
        <span class="v mono">{{
          formatMoney(
            selectedContact?.customAttributes?.total_deposits ||
              stats.deposits?.total
          )
        }}</span>
      </div>
      <div class="field">
        <span class="k">{{ t('CONTACTS_LAYOUT.PROFILE.TOTAL_CASHOUTS') }}</span>
        <span class="v mono">{{
          formatMoney(
            selectedContact?.customAttributes?.total_cashouts ||
              stats.cashouts?.total
          )
        }}</span>
      </div>
      <div class="field">
        <span class="k">{{ t('CONTACTS_LAYOUT.PROFILE.COUNTRY') }}</span>
        <span class="v">{{ countryDisplay }}</span>
      </div>
      <div class="field">
        <span class="k">{{
          t('CONTACTS_LAYOUT.PROFILE.VAULT_CURSOR_ID')
        }}</span>
        <span class="v mono">{{ vaultCursorId }}</span>
      </div>
    </div>

    <div class="card full profile-edit">
      <div class="card-t display">
        <span class="dot" />
        {{ t('CONTACTS_LAYOUT.CARD.EDIT_DETAILS_FORM.TITLE') }}
      </div>
      <ContactsForm
        ref="contactsFormRef"
        :contact-data="contactData"
        is-details-view
        @update="handleFormUpdate"
      />
      <button
        type="button"
        class="btn primary save-btn"
        :disabled="isUpdating || isFormInvalid"
        @click="updateContact"
      >
        {{ t('CONTACTS_LAYOUT.CARD.EDIT_DETAILS_FORM.UPDATE_BUTTON') }}
      </button>
    </div>

    <!-- QUICK ACTIONS — game ops panel -->
    <div class="card">
      <div class="card-t display">
        <span class="dot" />
        {{ t('GAMES.QUICK_ACTIONS.TITLE') }}
        <span class="ops-hint">{{ t('GAMES.QUICK_ACTIONS.LIVE_HINT') }}</span>
      </div>
      <GameQuickActionsPanel />
    </div>

    <slot name="tabs" />

    <Policy :permissions="['administrator']">
      <div class="card full">
        <div class="card-t display">
          <span class="dot" />
          {{ t('CONTACTS_LAYOUT.DETAILS.DELETE_CONTACT') }}
        </div>
        <p class="delete-desc">
          {{ t('CONTACTS_LAYOUT.DETAILS.DELETE_CONTACT_DESCRIPTION') }}
        </p>
        <button
          type="button"
          class="btn danger"
          @click="openConfirmDeleteContactDialog"
        >
          {{ t('CONTACTS_LAYOUT.DETAILS.DELETE_CONTACT') }}
        </button>
      </div>
      <ConfirmContactDeleteDialog
        ref="confirmDeleteContactDialogRef"
        :selected-contact="selectedContact"
        @go-to-contacts-list="emit('goToContactsList')"
      />
    </Policy>
  </div>
</template>

<style scoped>
.contact-details {
  display: contents;
}

.profile-edit :deep(.grid),
.profile-edit :deep(form) {
  display: grid;
  gap: 10px;
}

.save-btn {
  margin-top: 12px;
}

.delete-desc {
  font-size: 12.5px;
  color: var(--text-4);
  text-align: left;
  padding: 0 0 12px;
}

.patra-contact-actions {
  display: flex;
  gap: 8px;
  margin-bottom: 12px;
}
.patra-merge-btn,
.patra-send-msg-btn {
  flex: 1;
  padding: 8px 12px;
  border-radius: 8px;
  font-size: 12px;
  font-weight: 600;
  cursor: pointer;
  border: 1px solid var(--border-hi, #2e2940);
  background: var(--surface-2, #131119);
  color: var(--text, #ededf2);
  transition: all 0.2s;
}
.patra-merge-btn:hover,
.patra-send-msg-btn:hover {
  border-color: var(--patra, #6e56cf);
  color: var(--patra-3, #a78bfa);
}
.patra-send-msg-btn {
  background: linear-gradient(135deg, #6e56cf, #5b45b0);
  border-color: transparent;
  color: #fff;
}
.patra-send-msg-btn:hover {
  opacity: 0.9;
  color: #fff;
}
</style>
