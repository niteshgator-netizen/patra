<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';

import AccordionItem from 'dashboard/components/Accordion/AccordionItem.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ContactBlacklistAPI from 'dashboard/api/contactBlacklist';
import GameActionsAPI from 'dashboard/api/gameActions';
import PlayerBonusesAPI from 'dashboard/api/playerBonuses';
import { useUISettings } from 'dashboard/composables/useUISettings';

const props = defineProps({
  contact: {
    type: Object,
    default: null,
  },
  conversationId: {
    type: [Number, String],
    default: null,
  },
});

const { t } = useI18n();
const store = useStore();
const { uiSettings, updateUISettings } = useUISettings();

const bonuses = ref([]);
const cashouts = ref([]);
const loads = ref([]);
const blacklistReason = ref('');
const savingBlacklist = ref(false);
const agentNotes = ref('');
const savingNotes = ref(false);
const notesUpdatedAt = ref(null);
const profileOpen = computed({
  get: () => uiSettings.value.is_player_profile_open ?? true,
  set: val => updateUISettings({ is_player_profile_open: val }),
});
const vaultOpen = ref(true);

const attrs = computed(() => {
  const raw = props.contact?.custom_attributes;
  if (!raw || typeof raw !== 'object') return {};
  return { ...raw };
});

const paymentStatusPill = computed(() => props.contact?.payment_status || null);

const paymentPillClass = computed(() => {
  const color = paymentStatusPill.value?.color;
  const map = {
    green: 'tag engaged',
    blue: 'tag ai',
    yellow: 'tag',
  };
  return map[color] || 'tag';
});

const PREDEFINED_ATTR_KEYS = new Set([
  'game_username',
  'preferred_platform',
  'loyalty_tier',
  'deposit_count',
  'total_deposits',
  'total_cashouts',
  'last_deposit_amount',
  'last_deposit_date',
  'last_cashout_date',
  'last_cashout_intent_date',
  'preferred_payment_method',
  'preferred_bonus_percentage',
  'first_contact_date',
  'notes',
  'patra_finance_logs',
]);

function humanizeAttrKey(key) {
  return String(key)
    .replace(/_/g, ' ')
    .replace(/\b\w/g, c => c.toUpperCase());
}

function isPsidFacebookUrl(value) {
  return /^https?:\/\/(www\.)?facebook\.com\/\d{5,}\/?$/i.test(
    String(value || '').trim()
  );
}

function formatProfileFieldValue(key, value) {
  const normalizedKey = String(key).toLowerCase();
  if (
    (normalizedKey === 'facebook_profile' || normalizedKey === 'profile_url') &&
    isPsidFacebookUrl(value)
  ) {
    return t('CONTACT_PANEL.FACEBOOK_PROFILE_PSID_ONLY');
  }

  return typeof value === 'object' ? JSON.stringify(value) : String(value);
}

function formatMoney(val) {
  const n = Number.parseFloat(val);
  if (Number.isNaN(n)) return '—';
  return new Intl.NumberFormat(undefined, {
    style: 'currency',
    currency: 'USD',
    maximumFractionDigits: 2,
  }).format(n);
}

function formatDate(val) {
  if (!val) return '—';
  const d = new Date(val);
  if (Number.isNaN(d.getTime())) return String(val);
  return d.toLocaleDateString(undefined, {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  });
}

function humanizeGame(slug) {
  if (!slug) return slug;
  return String(slug)
    .replace(/_/g, ' ')
    .replace(/\b\w/g, c => c.toUpperCase());
}

function gameEmoji(slug) {
  const map = {
    game_vault: '🎰',
    juwa: '🐉',
    juwa_2: '🐉',
    ultra_panda: '🐼',
    vegas_sweeps: '🎲',
    milky_way: '🌌',
    fire_kirin: '🔥',
    panda_master: '🐼',
    game_room: '🎮',
  };
  return map[slug] || '🎮';
}

function maskPassword(password) {
  if (!password) return '—';
  const str = String(password);
  if (str.length <= 3) return '•••';
  return `•••••••${str.slice(-3)}`;
}

async function copyValue(value) {
  if (!value) return;
  await copyTextToClipboard(String(value));
  useAlert(t('CONTACT_PANEL.COPY_SUCCESSFUL'));
}

const rows = computed(() => [
  {
    key: 'game_username',
    label: t('PLAYER_PROFILE.FIELDS.GAME_USERNAME'),
    value: attrs.value.game_username,
  },
  {
    key: 'preferred_platform',
    label: t('PLAYER_PROFILE.FIELDS.PREFERRED_PLATFORM'),
    value: attrs.value.preferred_platform,
  },
  {
    key: 'deposit_count',
    label: t('PLAYER_PROFILE.FIELDS.DEPOSIT_COUNT'),
    value:
      attrs.value.deposit_count != null && attrs.value.deposit_count !== ''
        ? String(attrs.value.deposit_count)
        : '',
  },
  {
    key: 'total_deposits',
    label: t('PLAYER_PROFILE.FIELDS.TOTAL_DEPOSITS'),
    value: formatMoney(attrs.value.total_deposits),
    mono: true,
  },
  {
    key: 'total_cashouts',
    label: t('PLAYER_PROFILE.FIELDS.TOTAL_CASHOUTS'),
    value: formatMoney(attrs.value.total_cashouts),
    mono: true,
  },
  {
    key: 'last_deposit_amount',
    label: t('PLAYER_PROFILE.FIELDS.LAST_DEPOSIT_AMOUNT'),
    value: formatMoney(attrs.value.last_deposit_amount),
    mono: true,
  },
  {
    key: 'last_deposit_date',
    label: t('PLAYER_PROFILE.FIELDS.LAST_DEPOSIT_DATE'),
    value: formatDate(attrs.value.last_deposit_date),
  },
  {
    key: 'last_cashout_date',
    label: t('PLAYER_PROFILE.FIELDS.LAST_CASHOUT_DATE'),
    value: formatDate(attrs.value.last_cashout_date),
  },
  {
    key: 'preferred_bonus_percentage',
    label: t('PLAYER_PROFILE.FIELDS.PREFERRED_BONUS'),
    value:
      attrs.value.preferred_bonus_percentage != null &&
      attrs.value.preferred_bonus_percentage !== ''
        ? `${attrs.value.preferred_bonus_percentage}%`
        : '',
  },
  {
    key: 'first_contact_date',
    label: t('PLAYER_PROFILE.FIELDS.FIRST_CONTACT'),
    value: formatDate(attrs.value.first_contact_date),
  },
]);

const filledRows = computed(() =>
  rows.value.filter(r => r.value != null && String(r.value).trim() !== '')
);

const extraAttrRows = computed(() => {
  const out = [];
  Object.entries(attrs.value).forEach(([key, value]) => {
    if (PREDEFINED_ATTR_KEYS.has(key)) return;
    if (value == null || String(value).trim() === '') return;
    out.push({
      key: `extra_${key}`,
      label: humanizeAttrKey(key),
      value: formatProfileFieldValue(key, value),
    });
  });
  return out.sort((a, b) => a.label.localeCompare(b.label));
});

const displayRows = computed(() => [
  ...filledRows.value,
  ...extraAttrRows.value,
]);

function coerceFinanceLogs(val) {
  if (Array.isArray(val)) return val.filter(Boolean);
  if (val && typeof val === 'string') {
    try {
      const parsed = JSON.parse(val);
      return Array.isArray(parsed) ? parsed.filter(Boolean) : [];
    } catch {
      return [];
    }
  }
  return [];
}

function financeLogSortTs(entry) {
  const datePart = entry.transaction_date;
  const timePart = entry.transaction_time;
  if (datePart && timePart) {
    const d = new Date(`${datePart} ${timePart}`);
    if (!Number.isNaN(d.getTime())) return d.getTime();
  }
  if (datePart) {
    const d = new Date(datePart);
    if (!Number.isNaN(d.getTime())) return d.getTime();
  }
  const iso = entry.image_received_at || entry.logged_at;
  if (iso) {
    const d = new Date(iso);
    if (!Number.isNaN(d.getTime())) return d.getTime();
  }
  return 0;
}

const financeLogsSorted = computed(() => {
  const raw = coerceFinanceLogs(attrs.value.patra_finance_logs);
  return [...raw.entries()]
    .sort(([ia, a], [ib, b]) => {
      const tb = financeLogSortTs(b);
      const ta = financeLogSortTs(a);
      if (tb !== ta) return tb - ta;
      return ib - ia;
    })
    .map(([, e]) => e);
});

const financeLogsExpanded = ref(false);

function isFinanceFlagged(entry) {
  return Boolean(entry?.flag_reason);
}

function financeMemoLine(entry) {
  const raw = entry.note_or_memo;
  if (raw != null && String(raw).trim() !== '')
    return { type: 'memo', text: String(raw) };
  if (!isFinanceFlagged(entry)) return null;
  if (entry.flag_reason === 'recipient_mismatch') {
    const handle = entry.our_handle_name;
    if (handle != null && String(handle).trim() !== '') {
      return {
        type: 'flag',
        text: t('PLAYER_PROFILE.PAYMENT_SCREENSHOTS.EXPECTED_HANDLE', {
          handle: String(handle),
        }),
      };
    }
  }
  return {
    type: 'flag',
    text: t('PLAYER_PROFILE.PAYMENT_SCREENSHOTS.BONUS_NOT_APPLIED'),
  };
}

const financeLogsIndexed = computed(() =>
  financeLogsSorted.value.map((entry, globalIdx) => ({ entry, globalIdx }))
);

const financeLogsVisibleRows = computed(() => {
  const list = financeLogsIndexed.value;
  const sliced = financeLogsExpanded.value ? list : list.slice(0, 5);
  return sliced.map((row, visibleIdx) => {
    const prev = visibleIdx > 0 ? sliced[visibleIdx - 1].entry : null;
    const sameTxAsAbove =
      row.entry.flag_reason === 'duplicate' &&
      visibleIdx > 0 &&
      row.entry.transaction_id != null &&
      String(row.entry.transaction_id) !== '' &&
      prev &&
      String(prev.transaction_id) === String(row.entry.transaction_id);
    return {
      ...row,
      visibleIdx,
      sameTxAsAbove,
      memoLine: financeMemoLine(row.entry),
    };
  });
});

const financeLogsTotal = computed(() => financeLogsSorted.value.length);

const thumbLoadErrors = ref(new Set());

function financeRowDomKey(row) {
  return `${row.globalIdx}-${row.entry.transaction_id || ''}-${row.entry.logged_at || ''}`;
}

function onThumbError(row) {
  const k = financeRowDomKey(row);
  thumbLoadErrors.value = new Set(thumbLoadErrors.value).add(k);
}

function thumbErrored(row) {
  return thumbLoadErrors.value.has(financeRowDomKey(row));
}

function openFinanceFullImage(entry) {
  const url = entry.image_url || entry.image_thumb_url;
  if (!url) return;
  window.open(url, '_blank', 'noopener,noreferrer');
}

watch(
  () => props.contact?.id,
  () => {
    financeLogsExpanded.value = false;
    thumbLoadErrors.value = new Set();
  }
);

function financeStatusPill(entry) {
  const fr = entry.flag_reason;
  if (fr === 'duplicate') {
    return {
      text: t('PLAYER_PROFILE.PAYMENT_SCREENSHOTS.STATUS_DUPLICATE'),
      class: 'tag',
    };
  }
  if (fr === 'recipient_mismatch') {
    return {
      text: t('PLAYER_PROFILE.PAYMENT_SCREENSHOTS.STATUS_WRONG_RECIPIENT'),
      class: 'tag',
    };
  }
  if (fr === 'stale') {
    return {
      text: t('PLAYER_PROFILE.PAYMENT_SCREENSHOTS.STATUS_STALE'),
      class: 'tag',
    };
  }
  if (entry.kind === 'deposit') {
    return {
      text: t('PLAYER_PROFILE.PAYMENT_SCREENSHOTS.STATUS_CONFIRMED'),
      class: 'tag engaged',
    };
  }
  const kind = (entry.kind || '—').toString();
  return {
    text: kind ? kind.charAt(0).toUpperCase() + kind.slice(1) : '—',
    class: 'tag',
  };
}

const isBlacklisted = computed(
  () => attrs.value.blacklisted === true || attrs.value.blacklisted === 'true'
);

const gameCredentials = computed(() => {
  const creds = [];
  Object.entries(attrs.value).forEach(([key, value]) => {
    if (!key.endsWith('_username') || !value) return;
    const game = key.replace(/_username$/, '');
    const password = attrs.value[`${game}_password`];
    if (password) creds.push({ game, username: value, password });
  });
  return creds;
});

const paymentMethodDisplay = computed(() => {
  const method = (attrs.value.preferred_payment_method || '').toLowerCase();
  const icons = {
    cashapp: '💵 CashApp',
    venmo: '💰 Venmo',
    chime: '🏦 Chime',
    paypal: '💳 PayPal',
  };
  return icons[method] || attrs.value.preferred_payment_method || '';
});

const lifecycleStage = computed(() => attrs.value.lifecycle_stage || '');

const loyaltyTier = computed(() => attrs.value.loyalty_tier || '');

async function loadExtras() {
  if (!props.contact?.id) return;
  blacklistReason.value = attrs.value.blacklist_reason || '';
  agentNotes.value = attrs.value.agent_notes || attrs.value.notes || '';
  notesUpdatedAt.value = attrs.value.agent_notes_updated_at || null;
  try {
    const { data: bonusData } = await PlayerBonusesAPI.forContact(
      props.contact.id
    );
    bonuses.value = bonusData || [];
  } catch {
    bonuses.value = [];
  }
  try {
    const { data: cashoutData } = await GameActionsAPI.forContact(
      props.contact.id,
      'cashout'
    );
    cashouts.value = cashoutData || [];
  } catch {
    cashouts.value = [];
  }
  try {
    const { data: loadData } = await GameActionsAPI.forContact(
      props.contact.id,
      'load'
    );
    loads.value = loadData || [];
  } catch {
    loads.value = [];
  }
}

async function saveAgentNotes() {
  if (!props.contact?.id) return;
  savingNotes.value = true;
  try {
    const updatedAt = new Date().toISOString();
    await store.dispatch('contacts/update', {
      id: props.contact.id,
      custom_attributes: {
        ...attrs.value,
        agent_notes: agentNotes.value,
        agent_notes_updated_at: updatedAt,
      },
    });
    notesUpdatedAt.value = updatedAt;
    useAlert(t('PATRA.SETTINGS.SAVED'));
  } catch {
    useAlert(t('PATRA.SETTINGS.SAVE_ERROR'));
  } finally {
    savingNotes.value = false;
  }
}

async function toggleBlacklist() {
  savingBlacklist.value = true;
  try {
    await ContactBlacklistAPI.update(props.contact.id, {
      blacklisted: !isBlacklisted.value,
      blacklist_reason: blacklistReason.value,
    });
    useAlert(t('PATRA.SETTINGS.SAVED'));
    store.dispatch('contacts/show', { id: props.contact.id });
  } catch {
    useAlert(t('PATRA.SETTINGS.SAVE_ERROR'));
  } finally {
    savingBlacklist.value = false;
  }
}

async function sendCredentials(cred) {
  if (!props.conversationId) return;
  const content = `your ${cred.game} login — username: ${cred.username}, password: ${cred.password}`;
  await store.dispatch('createPendingMessageAndSend', {
    conversationId: props.conversationId,
    content,
    private: false,
  });
}

const toggleProfile = () => {
  profileOpen.value = !profileOpen.value;
};

const toggleVault = () => {
  vaultOpen.value = !vaultOpen.value;
};

onMounted(loadExtras);
watch(() => props.contact?.id, loadExtras);
</script>

<template>
  <div>
    <AccordionItem
      patra
      :title="$t('CONVERSATION_SIDEBAR.ACCORDION.PLAYER_PROFILE')"
      :is-open="profileOpen"
      compact
      @toggle="toggleProfile"
    >
      <div v-if="paymentStatusPill?.label" class="mb-3">
        <span class="tag" :class="paymentPillClass">{{
          paymentStatusPill.label
        }}</span>
      </div>
      <div class="field">
        <span class="k">{{ $t('BLACKLIST.TOGGLE') }}</span>
        <span class="v">
          <button
            type="button"
            class="mini-sw"
            :class="{ off: !isBlacklisted }"
            :disabled="savingBlacklist"
            @click="toggleBlacklist"
          >
            <i />
          </button>
        </span>
      </div>
      <input
        v-if="isBlacklisted || blacklistReason"
        v-model="blacklistReason"
        type="text"
        class="agent-notes mb-2"
        :placeholder="$t('BLACKLIST.REASON')"
      />
      <div v-if="paymentMethodDisplay" class="field">
        <span class="k">{{
          $t('PLAYER_PROFILE.FIELDS.PREFERRED_PAYMENT')
        }}</span>
        <span class="v">{{ paymentMethodDisplay }}</span>
      </div>
      <div class="sub-label">{{ $t('PLAYER_PROFILE.TIER_BADGE') }}</div>
      <div v-if="lifecycleStage" class="field">
        <span class="k">{{ $t('PLAYER_PROFILE.LIFECYCLE') }}</span>
        <span class="v">
          <span class="tag engaged">{{ lifecycleStage }}</span>
        </span>
      </div>
      <div v-if="loyaltyTier" class="field">
        <span class="k">{{ $t('PLAYER_PROFILE.FIELDS.LOYALTY_TIER') }}</span>
        <span class="v">
          <span class="tag new">{{ loyaltyTier }}</span>
        </span>
      </div>
      <div
        v-for="row in displayRows.filter(r =>
          [
            'total_deposits',
            'total_cashouts',
            'last_deposit_amount',
            'last_deposit_date',
          ].includes(r.key)
        )"
        :key="row.key"
        class="field"
      >
        <span class="k">{{ row.label }}</span>
        <span class="v" :class="{ mono: row.mono }">{{ row.value }}</span>
      </div>
      <div
        v-if="financeLogsTotal > 0"
        class="mt-3 pt-3 border-t border-[var(--border)]"
      >
        <div class="ctx-label mb-2">
          {{ $t('PLAYER_PROFILE.PAYMENT_SCREENSHOTS.SECTION_TITLE') }}
        </div>
        <div class="space-y-2">
          <div
            v-for="row in financeLogsVisibleRows"
            :key="financeRowDomKey(row)"
            class="flex gap-3 p-2 rounded-lg border border-[var(--border)]"
          >
            <button
              type="button"
              class="att-thumb shrink-0 !aspect-auto h-[72px] w-[56px]"
              :disabled="!(row.entry.image_thumb_url || row.entry.image_url)"
              @click="openFinanceFullImage(row.entry)"
            >
              <img
                v-if="
                  !thumbErrored(row) &&
                  (row.entry.image_thumb_url || row.entry.image_url)
                "
                :src="row.entry.image_thumb_url || row.entry.image_url"
                alt=""
                class="h-full w-full object-cover"
                @error="onThumbError(row)"
              />
              <span v-else class="text-lg">{{
                $t('PLAYER_PROFILE.PAYMENT_SCREENSHOTS.SCREENSHOT')
              }}</span>
            </button>
            <div class="min-w-0 flex-1 text-xs">
              <div class="flex flex-wrap items-center gap-1.5 mb-1">
                <span class="font-bold">{{
                  formatMoney(row.entry.amount)
                }}</span>
                <span :class="financeStatusPill(row.entry).class">
                  {{ financeStatusPill(row.entry).text }}
                </span>
              </div>
              <p v-if="row.memoLine" class="text-[var(--text-3)] m-0">
                {{ row.memoLine.text }}
              </p>
            </div>
          </div>
        </div>
        <Button
          v-if="financeLogsTotal > 5"
          class="mt-2 w-full"
          xs
          slate
          outline
          :label="
            financeLogsExpanded
              ? $t('PLAYER_PROFILE.PAYMENT_SCREENSHOTS.SHOW_RECENT')
              : $t('PLAYER_PROFILE.PAYMENT_SCREENSHOTS.VIEW_ALL', {
                  count: financeLogsTotal,
                })
          "
          @click="financeLogsExpanded = !financeLogsExpanded"
        />
      </div>
      <div
        v-if="bonuses.length"
        class="mt-3 pt-3 border-t border-[var(--border)]"
      >
        <div class="sub-label">{{ $t('PLAYER_PROFILE.BONUS_HISTORY') }}</div>
        <ul class="m-0 p-0 list-none text-xs text-[var(--text-3)] space-y-1">
          <li v-for="bonus in bonuses.slice(0, 5)" :key="bonus.id">
            {{ formatMoney(bonus.amount) }} —
            {{ bonus.reason || bonus.game_slug }}
          </li>
        </ul>
      </div>
      <div
        v-if="loads.length"
        class="mt-3 pt-3 border-t border-[var(--border)]"
      >
        <div class="sub-label">{{ $t('PLAYER_PROFILE.LOAD_HISTORY') }}</div>
        <ul class="m-0 p-0 list-none text-xs text-[var(--text-3)] space-y-1">
          <li v-for="load in loads.slice(0, 10)" :key="load.id">
            {{ formatDate(load.created_at) }} ·
            {{ load.game_slug || load.game_username }} ·
            {{ formatMoney(load.amount) }}
          </li>
        </ul>
      </div>
      <div
        v-if="cashouts.length"
        class="mt-3 pt-3 border-t border-[var(--border)]"
      >
        <div class="sub-label">{{ $t('PLAYER_PROFILE.CASHOUT_HISTORY') }}</div>
        <ul class="m-0 p-0 list-none text-xs text-[var(--text-3)] space-y-1">
          <li v-for="cashout in cashouts.slice(0, 10)" :key="cashout.id">
            {{ formatDate(cashout.created_at) }} ·
            {{ cashout.game_slug || cashout.game_username }} ·
            {{ formatMoney(cashout.amount) }}
          </li>
        </ul>
      </div>
    </AccordionItem>

    <AccordionItem patra :is-open="vaultOpen" compact @toggle="toggleVault">
      <template #title>
        {{ $t('CONTACTS_LAYOUT.PLAYER_VAULT.TITLE') }}
        <span v-if="gameCredentials.length" class="acc-badge">
          {{
            $t('CONTACTS_LAYOUT.PLAYER_VAULT.GAMES_COUNT', {
              count: gameCredentials.length,
            })
          }}
        </span>
      </template>
      <template v-if="gameCredentials.length">
        <div
          v-for="cred in gameCredentials"
          :key="cred.game"
          class="vault-card"
        >
          <div class="vault-game">
            <span class="vg-ic">{{ gameEmoji(cred.game) }}</span>
            {{ humanizeGame(cred.game) }}
          </div>
          <div class="vault-cred">
            <span class="vc-k">{{
              $t('CONTACTS_LAYOUT.PLAYER_VAULT.USER')
            }}</span>
            <span class="vc-v">{{ cred.username }}</span>
            <button
              type="button"
              class="vc-copy"
              :aria-label="$t('CONTACTS_LAYOUT.PLAYER_VAULT.COPY')"
              @click="copyValue(cred.username)"
            >
              {{ $t('CONTACTS_LAYOUT.PLAYER_VAULT.COPY') }}
            </button>
          </div>
          <div class="vault-cred">
            <span class="vc-k">{{
              $t('CONTACTS_LAYOUT.PLAYER_VAULT.PASS')
            }}</span>
            <span class="vc-v">{{ maskPassword(cred.password) }}</span>
            <button
              type="button"
              class="vc-copy"
              :aria-label="$t('CONTACTS_LAYOUT.PLAYER_VAULT.COPY')"
              @click="copyValue(cred.password)"
            >
              {{ $t('CONTACTS_LAYOUT.PLAYER_VAULT.COPY') }}
            </button>
          </div>
          <button
            v-if="conversationId"
            type="button"
            class="add-link mt-2"
            @click="sendCredentials(cred)"
          >
            {{ $t('PLAYER_PROFILE.SEND_CREDENTIALS') }}
          </button>
        </div>
      </template>
      <div v-else class="empty-note">
        {{ $t('CONTACTS_LAYOUT.PLAYER_VAULT.EMPTY') }}
      </div>
    </AccordionItem>

    <div class="ctx-section">
      <div class="ctx-label">{{ $t('PLAYER_PROFILE.AGENT_NOTES') }}</div>
      <textarea
        v-model="agentNotes"
        class="agent-notes"
        rows="3"
        :placeholder="$t('PLAYER_PROFILE.AGENT_NOTES_PLACEHOLDER')"
      />
      <p v-if="notesUpdatedAt" class="mt-1 text-[10px] text-[var(--text-3)]">
        {{
          $t('PLAYER_PROFILE.AGENT_NOTES_UPDATED', {
            time: formatDate(notesUpdatedAt),
          })
        }}
      </p>
      <button
        type="button"
        class="save-btn"
        :disabled="savingNotes"
        @click="saveAgentNotes"
      >
        {{ savingNotes ? '…' : $t('PATRA.SETTINGS.SAVE') }}
      </button>
    </div>
  </div>
</template>
