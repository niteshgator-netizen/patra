<script setup>
import { computed, ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useClipboard } from '@vueuse/core';
import { useRoute, useRouter } from 'vue-router';

import ContactsForm from 'dashboard/components-next/Contacts/ContactsForm/ContactsForm.vue';
import ConfirmContactDeleteDialog from 'dashboard/components-next/Contacts/ContactsForm/ConfirmContactDeleteDialog.vue';
import Policy from 'dashboard/components/policy.vue';
import GameQuickActionsPanel from 'dashboard/components/widgets/GameQuickActionsPanel.vue';
import PlayerTiersAPI from 'dashboard/api/playerTiers';
import types from 'dashboard/store/mutation-types';

const props = defineProps({
  selectedContact: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['goToContactsList']);

const { t } = useI18n();
const store = useStore();
const route = useRoute();
const router = useRouter();
const { copy, copied } = useClipboard();

const detailTab = ref('attributes');
const confirmDeleteContactDialogRef = ref(null);
const contactsFormRef = ref(null);
const contactData = ref({});
const playerTiers = ref([]);

const contactAttributeDefs = useMapGetter('attributes/getContactAttributes');
const contactActivities = ref([]);

const contactAttributes = computed(() => {
  const defs = contactAttributeDefs.value || [];
  const custom = props.selectedContact?.customAttributes || {};
  return defs
    .filter(attr => attr.attributeKey in custom)
    .map(attr => ({
      id: attr.id,
      attribute_display_name: attr.attributeDisplayName,
      value: custom[attr.attributeKey] ?? '',
    }));
});

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
  fetchTiers();

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

const fetchTiers = async () => {
  try {
    const { data } = await PlayerTiersAPI.getPlayerTiers(route.params.accountId);
    playerTiers.value = data;
  } catch (error) {
    console.error('Failed to fetch tiers:', error);
  }
};

const updateTier = async event => {
  const rawValue = event.target.value;
  const tierId = rawValue ? parseInt(rawValue, 10) : null;

  try {
    await PlayerTiersAPI.bulkAssignTier(
      route.params.accountId,
      [props.selectedContact.id],
      tierId
    );

    const tier = tierId
      ? playerTiers.value.find(item => item.id === tierId)
      : null;

    store.commit(types.SET_CONTACT_ITEM, {
      id: props.selectedContact.id,
      player_tier_id: tierId,
      player_tier: tier
        ? {
            id: tier.id,
            name: tier.name,
            color: tier.color,
            badge_text: tier.badge_text,
          }
        : null,
    });

    useAlert(t('CONTACTS_LAYOUT.PROFILE.PLAYER_TIER_SUCCESS'));
  } catch (error) {
    console.error('Failed to update tier:', error);
    useAlert(t('CONTACTS_LAYOUT.PROFILE.PLAYER_TIER_FAILED'));
  }
};
</script>

<template>
  <div class="contact-details">
    <div class="patra-contact-actions">
      <button type="button" class="patra-merge-btn" @click="openMerge">
        {{ $t('CONTACTS_LAYOUT.DETAIL_ACTIONS.MERGE') }}
      </button>
      <button type="button" class="patra-send-msg-btn" @click="sendMessage">
        {{ $t('CONTACTS_LAYOUT.DETAIL_ACTIONS.SEND_MESSAGE') }}
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
      <div class="field tier-field">
        <span class="k">{{ t('CONTACTS_LAYOUT.PROFILE.PLAYER_TIER') }}</span>
        <span class="v">
          <select
            :value="selectedContact?.playerTierId ?? ''"
            class="tier-select"
            @change="updateTier"
          >
            <option value="">{{ t('CONTACTS_LAYOUT.PROFILE.NO_TIER') }}</option>
            <option
              v-for="tier in playerTiers"
              :key="tier.id"
              :value="tier.id"
            >
              {{ tier.badge_text || tier.name }}
            </option>
          </select>
        </span>
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

    <div class="patra-dtabs">
      <button
        type="button"
        :class="['patra-dtab', { active: detailTab === 'attributes' }]"
        @click="detailTab = 'attributes'"
      >
        {{ $t('CONTACTS_LAYOUT.DETAIL_TABS.ATTRIBUTES') }}
      </button>
      <button
        type="button"
        :class="['patra-dtab', { active: detailTab === 'history' }]"
        @click="detailTab = 'history'"
      >
        {{ $t('CONTACTS_LAYOUT.DETAIL_TABS.HISTORY') }}
      </button>
      <button
        type="button"
        :class="['patra-dtab', { active: detailTab === 'notes' }]"
        @click="detailTab = 'notes'"
      >
        {{ $t('CONTACTS_LAYOUT.DETAIL_TABS.NOTES') }}
      </button>
      <button
        type="button"
        :class="['patra-dtab', { active: detailTab === 'media' }]"
        @click="detailTab = 'media'"
      >
        {{ $t('CONTACTS_LAYOUT.DETAIL_TABS.MEDIA') }}
      </button>
    </div>

    <div v-show="detailTab === 'attributes'" class="patra-tabpane">
      <div
        v-if="!contactAttributes || contactAttributes.length === 0"
        class="patra-empty-note"
      >
        {{ $t('CONTACTS_LAYOUT.DETAIL_EMPTY.ATTRIBUTES') }}
        <a @click="router.push({ name: 'settings_custom_attributes' })"
          >{{ $t('CONTACTS_LAYOUT.DETAIL_EMPTY.CREATE_IN_SETTINGS') }}</a
        >
      </div>
      <div v-else>
        <div
          v-for="attr in contactAttributes"
          :key="attr.id"
          class="patra-attr-row"
        >
          <span class="patra-attr-key">{{ attr.attribute_display_name }}</span>
          <span class="patra-attr-val">{{ attr.value || '-' }}</span>
        </div>
      </div>
    </div>

    <div v-show="detailTab === 'history'" class="patra-tabpane">
      <div
        v-if="!contactActivities || contactActivities.length === 0"
        class="patra-empty-note"
      >
        {{ $t('CONTACTS_LAYOUT.DETAIL_EMPTY.HISTORY') }}
      </div>
      <div v-else class="patra-timeline">
        <div
          v-for="act in contactActivities"
          :key="act.id"
          class="patra-tl-item"
        >
          <div class="patra-tl-dot" />
          <div class="patra-tl-body">
            <div class="patra-tl-title">{{ act.activity_type }}</div>
            <div class="patra-tl-time">{{ act.created_at }}</div>
          </div>
        </div>
      </div>
    </div>

    <div v-show="detailTab === 'notes'" class="patra-tabpane">
      <div class="patra-empty-note">{{ $t('CONTACTS_LAYOUT.DETAIL_EMPTY.NOTES') }}</div>
    </div>

    <div v-show="detailTab === 'media'" class="patra-tabpane">
      <div class="patra-empty-note">{{ $t('CONTACTS_LAYOUT.DETAIL_EMPTY.MEDIA') }}</div>
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

.tier-field .v {
  flex: 1;
}

.tier-select {
  width: 100%;
  padding: 8px 10px;
  border-radius: 8px;
  border: 1px solid var(--border-hi, #2e2940);
  background: var(--surface-2, #131119);
  color: var(--text, #ededf2);
  font-size: 12px;
}

.patra-dtabs {
  display: flex;
  border-bottom: 1px solid rgba(110, 86, 207, 0.15);
  margin: 8px 0;
}
.patra-dtab {
  flex: 1;
  padding: 8px 0;
  font-size: 11px;
  font-weight: 600;
  background: none;
  border: none;
  border-bottom: 2px solid transparent;
  color: #75727f;
  cursor: pointer;
  text-align: center;
}
.patra-dtab.active {
  color: #a78bfa;
  border-bottom-color: #6e56cf;
}
.patra-tabpane {
  padding: 8px 0;
  min-height: 60px;
}
.patra-empty-note {
  text-align: center;
  color: #75727f;
  font-size: 12px;
  padding: 20px 12px;
}
.patra-empty-note a {
  color: #8b5cf6;
  cursor: pointer;
}
.patra-timeline {
  padding: 0 8px;
}
.patra-tl-item {
  display: flex;
  gap: 10px;
  padding: 6px 0;
  border-left: 2px solid rgba(110, 86, 207, 0.2);
  margin-left: 6px;
  padding-left: 14px;
  position: relative;
}
.patra-tl-dot {
  position: absolute;
  left: -5px;
  top: 10px;
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: #6e56cf;
}
.patra-tl-title {
  font-size: 12px;
  /* A7: tokenized — hardcoded dark-theme hex broke light mode */
  color: var(--text, #1a1a24);
}
.patra-tl-time {
  font-size: 10px;
  color: #75727f;
}
.patra-attr-row {
  display: flex;
  justify-content: space-between;
  padding: 4px 0;
  font-size: 12px;
}
.patra-attr-key {
  color: #75727f;
}
.patra-attr-val {
  color: var(--text, #1a1a24);
}
</style>
