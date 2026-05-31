<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { dynamicTime } from 'shared/helpers/timeHelper';
import { format, parseISO } from 'date-fns';
import { picoSearch } from '@scmmishra/pico-search';

import Button from 'dashboard/components-next/button/Button.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import paymentHandlesApi from 'dashboard/api/paymentHandles';
import { useAccount } from 'dashboard/composables/useAccount';
import { useStore } from 'dashboard/composables/store';

defineOptions({
  name: 'PaymentHandlesSettings',
});

const { t } = useI18n();
const store = useStore();
const { currentAccount, updateAccount } = useAccount();

const DEFAULT_SCORING_CONFIG = {
  screenshot_present: 25,
  amount_match: 25,
  sender_match: 15,
  recipient_match: 10,
  txn_id_present: 10,
  email_confirmed: 10,
  note_match: 5,
  time_proximity: 5,
  time_proximity_minutes: 30,
  time_match: 5,
  auto_load_threshold: 80,
  escalate_threshold: 40,
  decline_threshold: 39,
};

const SCORING_PLATFORM_TABS = [
  { id: 'default', labelKey: 'PAYMENT_HANDLES.SCORING_TAB_DEFAULT' },
  { id: 'cashapp', labelKey: 'PAYMENT_HANDLES.PLATFORM_LABEL.CASHAPP' },
  { id: 'chime', labelKey: 'PAYMENT_HANDLES.PLATFORM_LABEL.CHIME' },
  { id: 'paypal', labelKey: 'PAYMENT_HANDLES.PLATFORM_LABEL.PAYPAL' },
  { id: 'venmo', labelKey: 'PAYMENT_HANDLES.PLATFORM_LABEL.VENMO' },
];

const SCORING_PLATFORM_IDS = SCORING_PLATFORM_TABS.map(tab => tab.id);
const SCORING_CONFIG_KEYS = Object.keys(DEFAULT_SCORING_CONFIG);

const SCORING_WEIGHT_FIELDS = [
  { key: 'screenshot_present', labelKey: 'PAYMENT_HANDLES.SCORING_SCREENSHOT' },
  { key: 'amount_match', labelKey: 'PAYMENT_HANDLES.SCORING_AMOUNT' },
  { key: 'sender_match', labelKey: 'PAYMENT_HANDLES.SCORING_SENDER' },
  { key: 'recipient_match', labelKey: 'PAYMENT_HANDLES.SCORING_RECIPIENT' },
  { key: 'txn_id_present', labelKey: 'PAYMENT_HANDLES.SCORING_TXN' },
  { key: 'email_confirmed', labelKey: 'PAYMENT_HANDLES.SCORING_EMAIL' },
  { key: 'note_match', labelKey: 'PAYMENT_HANDLES.SCORING_NOTE' },
];

const SCORING_THRESHOLD_FIELDS = [
  {
    key: 'auto_load_threshold',
    labelKey: 'PAYMENT_HANDLES.SCORING_AUTO_LOAD',
    prefix: '≥',
    inputClass: 'border-green-500/40 focus:ring-green-500/30',
  },
  {
    key: 'escalate_threshold',
    labelKey: 'PAYMENT_HANDLES.SCORING_ESCALATE',
    prefix: '≥',
    inputClass: 'border-amber-500/40 focus:ring-amber-500/30',
  },
  {
    key: 'decline_threshold',
    labelKey: 'PAYMENT_HANDLES.SCORING_DECLINE',
    prefix: '<',
    inputClass: 'border-red-500/40 focus:ring-red-500/30',
  },
];

const scoringSettingsOpen = ref(false);
const scoringFullConfig = ref({ default: { ...DEFAULT_SCORING_CONFIG } });
const customRules = ref([]);
const selectedScoringPlatform = ref('default');
const scoringPlatformDraft = ref({ ...DEFAULT_SCORING_CONFIG });
const scoringSaving = ref(false);
const platformEnabled = ref({});

const NON_DEFAULT_SCORING_PLATFORMS = SCORING_PLATFORM_IDS.filter(
  id => id !== 'default'
);

const parseNumericConfig = raw => {
  const entries = Object.entries(raw || {})
    .filter(
      ([key]) => SCORING_CONFIG_KEYS.includes(key) || key === 'note_present'
    )
    .map(([key, value]) => {
      const normalizedKey = key === 'note_present' ? 'note_match' : key;
      return [normalizedKey, Number(value)];
    });

  return Object.fromEntries(entries);
};

const effectiveDefaultConfig = () => ({
  ...DEFAULT_SCORING_CONFIG,
  ...(scoringFullConfig.value.default || {}),
});

const isPlatformInputsDisabled = computed(() => {
  if (selectedScoringPlatform.value === 'default') return false;
  return !platformEnabled.value[selectedScoringPlatform.value];
});

const syncDraftFromPlatform = () => {
  const defaults = effectiveDefaultConfig();
  if (selectedScoringPlatform.value === 'default') {
    scoringPlatformDraft.value = { ...defaults };
    return;
  }

  const override = scoringFullConfig.value[selectedScoringPlatform.value];
  scoringPlatformDraft.value = override
    ? { ...defaults, ...override }
    : { ...defaults };
};

const onPlatformEnabledChange = (platform, enabled) => {
  platformEnabled.value = { ...platformEnabled.value, [platform]: enabled };

  if (!enabled) {
    delete scoringFullConfig.value[platform];
    if (selectedScoringPlatform.value === platform) {
      syncDraftFromPlatform();
    }
  }
};

const isCurrentPlatformEnabled = computed({
  get() {
    if (selectedScoringPlatform.value === 'default') return true;
    return Boolean(platformEnabled.value[selectedScoringPlatform.value]);
  },
  set(enabled) {
    if (selectedScoringPlatform.value === 'default') return;
    onPlatformEnabledChange(selectedScoringPlatform.value, enabled);
  },
});

const persistDraftToPlatform = () => {
  const draft = parseNumericConfig(scoringPlatformDraft.value);

  if (selectedScoringPlatform.value === 'default') {
    scoringFullConfig.value.default = draft;
    return;
  }

  if (!platformEnabled.value[selectedScoringPlatform.value]) {
    delete scoringFullConfig.value[selectedScoringPlatform.value];
    return;
  }

  // Platform override is enabled — persist the FULL config explicitly so
  // thresholds (auto_load/escalate/decline) always save, even when equal to default.
  scoringFullConfig.value[selectedScoringPlatform.value] = { ...draft };
};

const showScoringOverrideIndicators = computed(
  () =>
    selectedScoringPlatform.value !== 'default' &&
    Boolean(platformEnabled.value[selectedScoringPlatform.value])
);

const isScoringFieldCustom = key => {
  const defaults = effectiveDefaultConfig();
  return Number(scoringPlatformDraft.value[key]) !== Number(defaults[key]);
};

const onScoringInput = () => {
  if (isPlatformInputsDisabled.value) return;
  persistDraftToPlatform();
};

const addCustomRule = () => {
  customRules.value.push({ name: '', points: 0 });
};

const removeCustomRule = index => {
  customRules.value.splice(index, 1);
};

const PLATFORMS = ['cashapp', 'chime', 'paypal', 'venmo', 'zelle'];
const STATUSES = ['active', 'failed', 'disabled'];

const IMAP_HOST_MAP = {
  'gmail.com': 'imap.gmail.com',
  'googlemail.com': 'imap.gmail.com',
  'outlook.com': 'outlook.office365.com',
  'hotmail.com': 'outlook.office365.com',
  'live.com': 'outlook.office365.com',
  'msn.com': 'outlook.office365.com',
  'yahoo.com': 'imap.mail.yahoo.com',
  'yahoo.co.uk': 'imap.mail.yahoo.com',
  'ymail.com': 'imap.mail.yahoo.com',
  'icloud.com': 'imap.mail.me.com',
  'me.com': 'imap.mail.me.com',
  'mac.com': 'imap.mail.me.com',
  'aol.com': 'imap.aol.com',
  'gmx.com': 'imap.gmx.com',
  'gmx.us': 'imap.gmx.com',
  'mail.com': 'imap.mail.com',
  'zoho.com': 'imap.zoho.com',
  'protonmail.com': '127.0.0.1',
  'pm.me': '127.0.0.1',
};

const IMAP_HOST_HINT =
  'Auto-detected from email. Override only if your provider uses a custom IMAP server.';

const handles = ref([]);
const isLoading = ref(true);
const searchQuery = ref('');
const showFormModal = ref(false);
const showDeleteModal = ref(false);
const formMode = ref('create');
const formSubmitting = ref(false);
const formErrors = ref([]);
const emailSectionOpen = ref(false);
const selectedRow = ref(null);
const editingId = ref(null);
const expandedLedgerId = ref(null);
const ledgerData = ref({});
const expandedLedgerRows = ref({});
const ledgerLoading = ref({});
const showScreenshotModal = ref(false);
const showEmailModal = ref(false);
const modalImageUrl = ref('');
const modalEmailContent = ref({});

const LEDGER_LABELS = {
  title: 'Payment ledger',
  export: 'Export CSV',
  score: 'Score',
  scoreBreakdown: 'Score Breakdown',
  scoreScreenshot: '📷 Screenshot',
  scoreAmountMatch: '💰 Amount match',
  scoreSenderMatch: '👤 Sender match',
  scoreRecipientMatch: '👤 Recipient match',
  scoreTxnId: '🔢 Txn ID',
  scoreEmailConfirmed: '📧 Email confirmed',
  scoreNoteMatch: '📝 Note match',
  scoreTimeProximity: '⏱ Time proximity',
  scoreTimeMatch: '⏱ Time match',
  scoreCustomRules: '⚙️ Custom rules',
  sender: 'Sender',
  txnId: 'Txn ID',
  dateTime: 'Date & time',
  note: 'Notes',
  status: 'Status',
  sourceScreenshot: '📷 Screenshot',
  sourceEmail: '📧 Email',
  awaitingEmail: '⏳ Awaiting email confirmation',
  screenshotPlaceholder: 'Payment screenshot preview',
  empty: 'No payment events yet.',
  ledgerToggle: 'Ledger',
  emailFrom: 'From',
  emailSubject: 'Subject',
  matchCheck: '✓',
};

const formatLedgerTime = raw => {
  if (!raw) return '—';
  try {
    const date = typeof raw === 'string' ? parseISO(raw) : new Date(raw);
    // parseISO/new Date can return an Invalid Date without throwing —
    // guard before format() or it raises RangeError and crashes the ledger.
    if (!date || Number.isNaN(date.getTime())) {
      return typeof raw === 'string' ? raw : '—';
    }
    return format(date, 'MMM d, yyyy h:mm a');
  } catch {
    return typeof raw === 'string' ? raw : '—';
  }
};

const safeDynamicTime = value => {
  if (!value) return '—';
  try {
    const d = typeof value === 'string' ? parseISO(value) : new Date(value);
    if (!d || Number.isNaN(d.getTime())) return '—';
    return dynamicTime(value);
  } catch {
    return '—';
  }
};

const formatScreenshotDateTime = entry => {
  const screenshotDateTime =
    entry.transaction_time || entry.transaction_date || entry.image_received_at;
  if (!screenshotDateTime) return '—';
  if (entry.transaction_time || entry.transaction_date) {
    const parts = [entry.transaction_date, entry.transaction_time].filter(
      Boolean
    );
    return parts.join(' · ');
  }
  return formatLedgerTime(screenshotDateTime);
};

const SCORE_BREAKDOWN_THRESHOLD_KEYS = new Set([
  'auto_load_threshold',
  'escalate_threshold',
  'decline_threshold',
  'total',
]);

const SCORE_BREAKDOWN_META_KEYS = new Set([
  ...SCORE_BREAKDOWN_THRESHOLD_KEYS,
  'max',
  'weights',
  'platform_config',
  'config',
  'time_proximity_minutes',
]);

const SCORE_BREAKDOWN_ORDER = [
  'screenshot',
  'amount_match',
  'sender_match',
  'recipient_match',
  'txn_id',
  'email_confirmed',
  'note_match',
  'time_proximity',
  'time_match',
  'custom_rules',
];

const SCORE_BREAKDOWN_LABELS = {
  screenshot: LEDGER_LABELS.scoreScreenshot,
  amount_match: LEDGER_LABELS.scoreAmountMatch,
  sender_match: LEDGER_LABELS.scoreSenderMatch,
  recipient_match: LEDGER_LABELS.scoreRecipientMatch,
  txn_id: LEDGER_LABELS.scoreTxnId,
  email_confirmed: LEDGER_LABELS.scoreEmailConfirmed,
  note_match: LEDGER_LABELS.scoreNoteMatch,
  time_proximity: LEDGER_LABELS.scoreTimeProximity,
  time_match: LEDGER_LABELS.scoreTimeMatch,
  custom_rules: LEDGER_LABELS.scoreCustomRules,
};

const SCORE_BREAKDOWN_CONFIG_KEY_MAP = {
  screenshot: 'screenshot_present',
  txn_id: 'txn_id_present',
};

const getScoreComponentEarned = value => {
  if (value == null) return 0;
  if (Array.isArray(value)) {
    return value.reduce(
      (sum, rule) => sum + (Number(rule?.points ?? rule?.earned ?? rule) || 0),
      0
    );
  }
  if (typeof value === 'object') {
    return Number(value.earned ?? value.points ?? value.score ?? 0) || 0;
  }
  return Number(value) || 0;
};

const getScoreComponentMax = (breakdown, key) => {
  const value = breakdown[key];
  if (value && typeof value === 'object' && !Array.isArray(value)) {
    if (value.max != null) return Number(value.max);
  }

  const maxConfig =
    breakdown.max || breakdown.weights || breakdown.platform_config;
  if (maxConfig && typeof maxConfig === 'object') {
    const configKey = SCORE_BREAKDOWN_CONFIG_KEY_MAP[key] || key;
    if (maxConfig[configKey] != null) return Number(maxConfig[configKey]);
    if (maxConfig[key] != null) return Number(maxConfig[key]);
  }

  return null;
};

const formatScoreBreakdownValue = (earned, max) => {
  if (max != null && !Number.isNaN(max)) return `${earned}/${max}`;
  return String(earned);
};

const getScoreBreakdownRows = breakdown => {
  if (!breakdown || typeof breakdown !== 'object') return [];

  const keys = Object.keys(breakdown).filter(
    key => !SCORE_BREAKDOWN_META_KEYS.has(key)
  );

  const sortIndex = key => {
    const index = SCORE_BREAKDOWN_ORDER.indexOf(key);
    return index === -1 ? SCORE_BREAKDOWN_ORDER.length : index;
  };

  return keys
    .sort((a, b) => sortIndex(a) - sortIndex(b))
    .map(key => {
      const earned = getScoreComponentEarned(breakdown[key]);
      const max = getScoreComponentMax(breakdown, key);
      return {
        key,
        label: SCORE_BREAKDOWN_LABELS[key] || key.replace(/_/g, ' '),
        earned,
        display: formatScoreBreakdownValue(earned, max),
      };
    });
};

const mapLedgerEntry = (entry, index) => ({
  id: entry.transaction_id || entry.image_received_at || `ledger-${index}`,
  raw: entry,
  amount: entry.amount,
  platform: entry.platform,
  score: entry.confidence_score ?? entry.resolve_score ?? null,
  score_breakdown: entry.score_breakdown || null,
  status: entry.status || 'Screenshot Received',
  note: entry.note_or_memo || '—',
  headerTime: formatScreenshotDateTime(entry),
  screenshot: {
    sender:
      entry.sender_name || entry.sender_display || entry.sender_handle || '—',
    txnId: entry.transaction_id || '—',
    time: formatScreenshotDateTime(entry),
    note: entry.note_or_memo || '—',
    imageUrl: entry.image_url,
  },
  email: {
    sender: entry.email_sender_name || '—',
    subject: entry.email_subject || '—',
    date: formatLedgerTime(entry.email_date),
    note: entry.note_or_memo || '—',
    from: entry.email_from || '—',
    body: entry.email_body_snippet || '',
    confirmed: entry.email_confirmed === true,
  },
});

const form = ref({
  platform: 'cashapp',
  handle: '',
  display_name: '',
  priority: 1,
  status: 'active',
  notes: '',
  verification_email: '',
  verification_email_password: '',
  verification_email_host: '',
  verification_email_port: 993,
  verification_email_ssl: true,
});

const sortedHandles = computed(() =>
  [...handles.value].sort((a, b) => {
    if (a.platform !== b.platform) return a.platform.localeCompare(b.platform);
    return (a.priority || 0) - (b.priority || 0);
  })
);

const filteredRecords = computed(() => {
  const query = searchQuery.value.trim();
  if (!query) return sortedHandles.value;
  return picoSearch(sortedHandles.value, query, [
    'platform',
    'handle',
    'display_name',
    'status',
  ]);
});

const tableHeaders = computed(() => [
  t('PAYMENT_HANDLES.LIST.TABLE_HEADER.PLATFORM'),
  t('PAYMENT_HANDLES.LIST.TABLE_HEADER.HANDLE'),
  t('PAYMENT_HANDLES.LIST.TABLE_HEADER.DISPLAY_NAME'),
  t('PAYMENT_HANDLES.LIST.TABLE_HEADER.PRIORITY'),
  t('PAYMENT_HANDLES.LIST.TABLE_HEADER.STATUS'),
  t('PAYMENT_HANDLES.LIST.TABLE_HEADER.FAILURE_COUNT'),
  t('PAYMENT_HANDLES.LIST.TABLE_HEADER.LAST_FAILED'),
  LEDGER_LABELS.ledgerToggle,
  t('PAYMENT_HANDLES.LIST.TABLE_HEADER.ACTIONS'),
]);

const deleteMessage = computed(() => ` ${selectedRow.value?.handle || ''}?`);

const platformLabel = id => {
  const key = `PAYMENT_HANDLES.PLATFORM_LABEL.${String(id || '').toUpperCase()}`;
  const out = t(key);
  return out === key ? id : out;
};

const statusLabel = status => {
  const key = `PAYMENT_HANDLES.STATUS.${String(status || '').toUpperCase()}`;
  const out = t(key);
  return out === key ? status : out;
};

const platformIconMeta = platform => {
  const p = String(platform || '').toLowerCase();
  const map = {
    cashapp: { abbr: 'CA', bg: '#00D632' },
    chime: { abbr: 'CH', bg: '#1EC677' },
    paypal: { abbr: 'PP', bg: '#0070BA' },
    venmo: { abbr: 'VE', bg: '#3D95CE' },
    zelle: { abbr: 'ZE', bg: '#6B1FD6' },
  };
  return (
    map[p] || {
      abbr: String(platform || '??')
        .slice(0, 2)
        .toUpperCase(),
      bg: '#54515e',
    }
  );
};

const statusBadgeClass = status => {
  if (status === 'active') return 'st-active';
  if (status === 'failed') return 'st-failed';
  return 'st-disabled';
};

const failCountClass = count => {
  const n = Number(count) || 0;
  return n > 0 ? 'fc bad' : 'fc';
};

const getPaymentEvents = handle => ledgerData.value[handle.id] || [];

const isLedgerLoading = handleId => Boolean(ledgerLoading.value[handleId]);

const loadLedger = async handleId => {
  ledgerLoading.value = { ...ledgerLoading.value, [handleId]: true };
  try {
    const { data } = await paymentHandlesApi.ledger(handleId);
    const entries = Array.isArray(data) ? data : [];
    ledgerData.value = {
      ...ledgerData.value,
      [handleId]: entries.map(mapLedgerEntry),
    };
  } catch {
    useAlert(t('PAYMENT_HANDLES.ERROR_GENERIC'));
    ledgerData.value = { ...ledgerData.value, [handleId]: [] };
  } finally {
    ledgerLoading.value = { ...ledgerLoading.value, [handleId]: false };
  }
};

const toggleLedger = handleId => {
  if (expandedLedgerId.value === handleId) {
    expandedLedgerId.value = null;
    return;
  }

  expandedLedgerId.value = handleId;
  if (!ledgerData.value[handleId]) {
    loadLedger(handleId);
  }
};

const isLedgerOpen = handleId => expandedLedgerId.value === handleId;

const formatLedgerAmount = amount => {
  if (amount == null || amount === '') return '—';
  const num = Number(amount);
  if (Number.isNaN(num)) return '—';
  return `$${num % 1 === 0 ? num.toFixed(0) : num.toFixed(2)}`;
};

const platformBadgeClass = platform => {
  const p = String(platform || '').toLowerCase();
  if (p === 'paypal') return 'bg-blue-500/15 text-blue-700 border-blue-500/30';
  if (p === 'cashapp')
    return 'bg-green-500/15 text-green-700 border-green-500/30';
  if (p === 'venmo') return 'bg-sky-500/15 text-sky-700 border-sky-500/30';
  if (p === 'chime') return 'bg-teal-500/15 text-teal-700 border-teal-500/30';
  if (p === 'zelle')
    return 'bg-purple-500/15 text-purple-700 border-purple-500/30';
  return 'bg-n-slate-4 text-n-slate-11 border-n-weak';
};

const scoreBarClass = score => {
  if (score == null) return 'bg-n-slate-4';
  if (score >= 70) return 'bg-green-500';
  if (score >= 40) return 'bg-amber-500';
  return 'bg-red-500';
};

const scoreTextClass = score => {
  if (score == null) return 'text-n-slate-11';
  if (score >= 70) return 'text-green-700 dark:text-green-400';
  if (score >= 40) return 'text-amber-700 dark:text-amber-300';
  return 'text-red-700 dark:text-red-400';
};

const ledgerStatusSummary = event => {
  const status = String(event.status || '').toLowerCase();
  const flag = String(event.raw?.flag_reason || '').toLowerCase();
  const game = event.raw?.loaded_game_slug;
  const user = event.raw?.loaded_game_username;

  if (status.includes('loaded')) {
    return {
      color: 'green',
      label: 'LOADED',
      reason: game && user ? `Loaded to ${user} on ${game}` : 'Loaded to game',
    };
  }
  if (flag.includes('duplicate')) {
    return {
      color: 'red',
      label: 'DUPLICATE',
      reason: 'Same screenshot already loaded — blocked',
    };
  }
  if (flag.includes('mismatch')) {
    return {
      color: 'red',
      label: 'MISMATCH',
      reason: 'Recipient did not match the handle',
    };
  }
  if (status.includes('verified')) {
    return {
      color: 'amber',
      label: 'AWAITING GAME',
      reason: 'Verified — waiting for customer to pick a game',
    };
  }
  if (status.includes('screenshot received')) {
    return {
      color: 'amber',
      label: 'CHECKING',
      reason: 'Screenshot received — verifying with bank email',
    };
  }
  return {
    color: 'slate',
    label: event.status || 'PENDING',
    reason: '',
  };
};

const stripColorClass = color =>
  ({
    green: 'border-l-green-500',
    amber: 'border-l-amber-400',
    red: 'border-l-red-500',
    blue: 'border-l-blue-500',
    slate: 'border-l-n-slate-6',
  })[color] || 'border-l-n-slate-6';

const stripBadgeClass = color =>
  ({
    green: 'bg-green-500/15 text-green-700 dark:text-green-400',
    amber: 'bg-amber-500/15 text-amber-800 dark:text-amber-300',
    red: 'bg-red-500/15 text-red-700 dark:text-red-400',
    blue: 'bg-blue-500/15 text-blue-700 dark:text-blue-400',
    slate: 'bg-n-slate-4 text-n-slate-11',
  })[color] || 'bg-n-slate-4 text-n-slate-11';

const toggleLedgerRow = id => {
  expandedLedgerRows.value = {
    ...expandedLedgerRows.value,
    [id]: !expandedLedgerRows.value[id],
  };
};

const isLedgerRowExpanded = id => Boolean(expandedLedgerRows.value[id]);

const emailAmountMatches = event =>
  event.raw?.email_amount != null &&
  event.raw?.amount != null &&
  Number(event.raw.email_amount) === Number(event.raw.amount);

const emailSenderMatches = event => {
  const screenshotSender = String(event.raw?.sender_name || '')
    .toLowerCase()
    .trim();
  const emailSender = String(event.raw?.email_sender_name || '')
    .toLowerCase()
    .trim();
  if (!screenshotSender || !emailSender) return false;
  const first = screenshotSender.split(/\s+/)[0];
  return (
    emailSender.includes(first) ||
    screenshotSender.includes(emailSender.split(/\s+/)[0])
  );
};

const emailDateMatches = event => {
  if (!event.raw?.email_date || !event.raw?.image_received_at) return false;
  try {
    const emailTime = parseISO(event.raw.email_date);
    const imageTime = parseISO(event.raw.image_received_at);
    return Math.abs(emailTime - imageTime) < 30 * 60 * 1000;
  } catch {
    return false;
  }
};

const hasEmailRowData = event =>
  event.email.confirmed &&
  (event.email.sender !== '—' ||
    event.email.subject !== '—' ||
    event.email.body);

const openScreenshotModal = url => {
  if (!url) return;
  modalImageUrl.value = url;
  showScreenshotModal.value = true;
};

const openEmailModal = event => {
  modalEmailContent.value = {
    from: event.email.from,
    subject: event.email.subject,
    date: event.email.date,
    body: event.email.body,
  };
  showEmailModal.value = true;
};

const closeScreenshotModal = () => {
  showScreenshotModal.value = false;
  modalImageUrl.value = '';
};

const closeEmailModal = () => {
  showEmailModal.value = false;
  modalEmailContent.value = {};
};

const exportLedger = handle => {
  const events = getPaymentEvents(handle);
  const blob = new Blob([JSON.stringify(events, null, 2)], {
    type: 'application/json',
  });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = `payment-ledger-${handle.handle || handle.id}.json`;
  link.click();
  URL.revokeObjectURL(url);
};

const loadScoringConfig = () => {
  const saved =
    currentAccount.value?.custom_attributes?.payment_scoring_config || {};
  const isNested = saved.default && typeof saved.default === 'object';

  scoringFullConfig.value = { default: { ...DEFAULT_SCORING_CONFIG } };
  platformEnabled.value = Object.fromEntries(
    NON_DEFAULT_SCORING_PLATFORMS.map(platformId => [platformId, false])
  );

  if (isNested) {
    scoringFullConfig.value.default = {
      ...DEFAULT_SCORING_CONFIG,
      ...parseNumericConfig(saved.default),
    };
    SCORING_PLATFORM_IDS.filter(id => id !== 'default').forEach(platformId => {
      if (saved[platformId] && typeof saved[platformId] === 'object') {
        scoringFullConfig.value[platformId] = parseNumericConfig(
          saved[platformId]
        );
      }
    });
    NON_DEFAULT_SCORING_PLATFORMS.forEach(platformId => {
      const override = scoringFullConfig.value[platformId];
      platformEnabled.value[platformId] = Boolean(
        override && Object.keys(override).length
      );
    });
  } else {
    const { custom_rules: _customRules, ...flatConfig } = saved;
    scoringFullConfig.value.default = {
      ...DEFAULT_SCORING_CONFIG,
      ...parseNumericConfig(flatConfig),
    };
  }

  customRules.value = Array.isArray(saved.custom_rules)
    ? saved.custom_rules.map(rule => ({
        name: rule.name || '',
        points: Number(rule.points) || 0,
      }))
    : [];

  syncDraftFromPlatform();
};

const saveScoringConfig = async () => {
  persistDraftToPlatform();
  scoringSaving.value = true;
  try {
    const payment_scoring_config = {
      default: scoringFullConfig.value.default || { ...DEFAULT_SCORING_CONFIG },
      custom_rules: customRules.value
        .filter(rule => rule.name.trim())
        .map(rule => ({
          name: rule.name.trim(),
          points: Number(rule.points) || 0,
        })),
    };

    SCORING_PLATFORM_IDS.filter(id => id !== 'default').forEach(platformId => {
      if (scoringFullConfig.value[platformId]) {
        payment_scoring_config[platformId] =
          scoringFullConfig.value[platformId];
      }
    });

    const payload = { custom_attributes: { payment_scoring_config } };
    await updateAccount(payload);
    useAlert(t('PAYMENT_HANDLES.SCORING_SAVED'));
  } catch {
    useAlert(t('PAYMENT_HANDLES.ERROR_GENERIC'));
  } finally {
    scoringSaving.value = false;
  }
};

const loadHandles = async () => {
  isLoading.value = true;
  try {
    const { data } = await paymentHandlesApi.get();
    handles.value = Array.isArray(data) ? data : [];
  } catch {
    useAlert(t('PAYMENT_HANDLES.ERROR_GENERIC'));
    handles.value = [];
  } finally {
    isLoading.value = false;
  }
};

const resetForm = () => {
  formErrors.value = [];
  form.value = {
    platform: 'cashapp',
    handle: '',
    display_name: '',
    priority: 1,
    status: 'active',
    notes: '',
    verification_email: '',
    verification_email_password: '',
    verification_email_host: '',
    verification_email_port: 993,
    verification_email_ssl: true,
  };
  emailSectionOpen.value = false;
};

const openCreate = () => {
  formMode.value = 'create';
  editingId.value = null;
  resetForm();
  showFormModal.value = true;
};

const hideFormModal = () => {
  showFormModal.value = false;
};

const openEdit = row => {
  formMode.value = 'edit';
  editingId.value = row.id;
  formErrors.value = [];
  form.value = {
    platform: row.platform,
    handle: row.handle,
    display_name: row.display_name || '',
    priority: row.priority,
    status: row.status,
    notes: row.notes || '',
    verification_email: row.verification_email || '',
    verification_email_password: '',
    verification_email_host: row.verification_email_host || '',
    verification_email_port: row.verification_email_port || 993,
    verification_email_ssl: row.verification_email_ssl !== false,
  };
  emailSectionOpen.value = Boolean(
    row.verification_email || row.verification_email_host
  );
  showFormModal.value = true;
};

const submitForm = async () => {
  formSubmitting.value = true;
  formErrors.value = [];
  try {
    const payload = {
      payment_handle: {
        platform: form.value.platform,
        handle: form.value.handle.trim(),
        display_name: form.value.display_name.trim(),
        priority: Number(form.value.priority),
        status: form.value.status,
        notes: form.value.notes,
        verification_email: form.value.verification_email || null,
        verification_email_host: form.value.verification_email_host || null,
        verification_email_port:
          Number(form.value.verification_email_port) || 993,
        verification_email_ssl: form.value.verification_email_ssl,
      },
    };
    if (form.value.verification_email_password.trim()) {
      payload.payment_handle.verification_email_password =
        form.value.verification_email_password;
    }

    if (formMode.value === 'create') {
      await paymentHandlesApi.create(payload);
      useAlert(t('PAYMENT_HANDLES.SUCCESS_CREATED'));
    } else {
      await paymentHandlesApi.update(editingId.value, payload);
      useAlert(t('PAYMENT_HANDLES.SUCCESS_UPDATED'));
    }
    hideFormModal();
    await loadHandles();
  } catch (e) {
    const errs = e?.response?.data?.errors;
    formErrors.value = Array.isArray(errs) ? errs : [];
    if (!formErrors.value.length) {
      useAlert(t('PAYMENT_HANDLES.ERROR_GENERIC'));
    }
  } finally {
    formSubmitting.value = false;
  }
};

const openDelete = row => {
  selectedRow.value = row;
  showDeleteModal.value = true;
};

const closeDelete = () => {
  showDeleteModal.value = false;
};

const confirmDelete = async () => {
  if (!selectedRow.value) return;
  try {
    await paymentHandlesApi.delete(selectedRow.value.id);
    useAlert(t('PAYMENT_HANDLES.SUCCESS_DELETED'));
    closeDelete();
    await loadHandles();
  } catch {
    useAlert(t('PAYMENT_HANDLES.ERROR_GENERIC'));
  }
};

const detectImapHostFromEmail = email => {
  const e = (email || '').toString().toLowerCase().trim();
  const at = e.indexOf('@');
  if (at < 0) return null;
  const domain = e.slice(at + 1);
  return IMAP_HOST_MAP[domain] || null;
};

watch(
  () => form.value.verification_email,
  newEmail => {
    const detected = detectImapHostFromEmail(newEmail);
    if (detected) {
      form.value.verification_email_host = detected;
    }
  }
);

onMounted(async () => {
  await store.dispatch('accounts/get', { silent: true });
  loadScoringConfig();
  loadHandles();
});

watch(currentAccount, () => {
  loadScoringConfig();
});

watch(selectedScoringPlatform, () => {
  syncDraftFromPlatform();
});
</script>

<template>
  <SettingsLayout
    class="pat-ph-wrap"
    :is-loading="isLoading"
    :loading-message="t('PAYMENT_HANDLES.LOADING')"
    :no-records-found="!handles.length"
    :no-records-message="t('PAYMENT_HANDLES.EMPTY')"
  >
    <template #header>
      <BaseSettingsHeader
        v-model:search-query="searchQuery"
        :title="t('PAYMENT_HANDLES.TITLE')"
        :description="t('PAYMENT_HANDLES.DESCRIPTION')"
        feature-name="payment_handles"
        :search-placeholder="t('PAYMENT_HANDLES.SEARCH_PLACEHOLDER')"
        :back-button-label="$t('SIDEBAR.INTEGRATIONS')"
      />

      <div v-show="scoringSettingsOpen" class="ph-scoring-panel">
        <div class="mb-4 flex flex-wrap gap-1 border-b border-[#DDD8F5]">
          <button
            v-for="tab in SCORING_PLATFORM_TABS"
            :key="tab.id"
            type="button"
            class="rounded-t-lg px-3 py-2 text-xs font-medium transition-colors"
            :class="
              selectedScoringPlatform === tab.id
                ? 'border-b-2 border-[#6E56CF] bg-[#F0EDFF]/60 text-[#4C3799]'
                : 'text-n-slate-11 hover:bg-[#F0EDFF]/30 hover:text-[#4C3799]'
            "
            @click="selectedScoringPlatform = tab.id"
          >
            {{ t(tab.labelKey) }}
          </button>
        </div>

        <div
          v-if="selectedScoringPlatform !== 'default'"
          class="mb-3 flex items-center gap-3"
        >
          <Switch v-model="isCurrentPlatformEnabled" />
          <span class="text-sm text-n-slate-12">
            {{
              t('PAYMENT_HANDLES.SCORING_USE_CUSTOM', {
                platform: platformLabel(selectedScoringPlatform),
              })
            }}
          </span>
        </div>

        <p
          v-if="isPlatformInputsDisabled"
          class="mb-3 text-xs italic text-n-slate-11"
        >
          {{ t('PAYMENT_HANDLES.SCORING_USING_DEFAULT') }}
        </p>

        <div class="grid gap-6 lg:grid-cols-2">
          <div>
            <h3
              class="mb-3 text-xs font-semibold uppercase tracking-wide text-n-slate-11"
            >
              {{ t('PAYMENT_HANDLES.SCORING_WEIGHTS_TITLE') }}
            </h3>
            <div class="overflow-hidden rounded-lg border border-n-weak">
              <div
                class="grid grid-cols-[1fr_5rem] gap-2 border-b border-n-weak bg-n-alpha-2 px-3 py-2 text-[11px] font-medium text-n-slate-11"
              >
                <span>{{ t('PAYMENT_HANDLES.SCORING_WEIGHTS_TITLE') }}</span>
                <span>{{ t('PAYMENT_HANDLES.SCORING_POINTS') }}</span>
              </div>
              <div
                v-for="field in SCORING_WEIGHT_FIELDS"
                :key="field.key"
                class="grid grid-cols-[1fr_5rem] items-center gap-2 border-b border-n-weak/70 px-3 py-2"
              >
                <span
                  class="text-sm"
                  :class="
                    isPlatformInputsDisabled
                      ? 'text-n-slate-10'
                      : 'text-n-slate-12'
                  "
                >
                  {{ t(field.labelKey) }}
                </span>
                <div class="flex flex-col items-end gap-0.5">
                  <input
                    v-model.number="scoringPlatformDraft[field.key]"
                    type="number"
                    min="0"
                    max="100"
                    :disabled="isPlatformInputsDisabled"
                    class="h-8 w-full rounded-md border border-n-weak bg-n-alpha-3 px-2 text-sm"
                    :class="
                      isPlatformInputsDisabled
                        ? 'text-n-slate-10 opacity-60'
                        : 'text-n-slate-12'
                    "
                    @input="onScoringInput"
                  />
                  <span
                    v-if="showScoringOverrideIndicators"
                    class="text-[10px] leading-none"
                    :class="
                      isScoringFieldCustom(field.key)
                        ? 'text-purple-600 dark:text-purple-400'
                        : 'text-n-slate-10'
                    "
                  >
                    {{
                      isScoringFieldCustom(field.key)
                        ? t('PAYMENT_HANDLES.SCORING_FIELD_CUSTOM')
                        : t('PAYMENT_HANDLES.SCORING_FIELD_DEFAULT')
                    }}
                  </span>
                </div>
              </div>
              <div
                class="grid grid-cols-[1fr_auto] items-center gap-2 px-3 py-2"
              >
                <span
                  class="text-sm"
                  :class="
                    isPlatformInputsDisabled
                      ? 'text-n-slate-10'
                      : 'text-n-slate-12'
                  "
                >
                  {{ t('PAYMENT_HANDLES.SCORING_TIME') }}
                </span>
                <div class="flex flex-wrap items-center justify-end gap-2">
                  <span class="text-xs text-n-slate-11">
                    {{ t('PAYMENT_HANDLES.SCORING_POINTS') }}:
                  </span>
                  <div class="flex flex-col items-end gap-0.5">
                    <input
                      v-model.number="scoringPlatformDraft.time_proximity"
                      type="number"
                      min="0"
                      max="100"
                      :disabled="isPlatformInputsDisabled"
                      class="h-8 w-16 rounded-md border border-n-weak bg-n-alpha-3 px-2 text-sm"
                      :class="
                        isPlatformInputsDisabled
                          ? 'text-n-slate-10 opacity-60'
                          : 'text-n-slate-12'
                      "
                      @input="onScoringInput"
                    />
                    <span
                      v-if="showScoringOverrideIndicators"
                      class="text-[10px] leading-none"
                      :class="
                        isScoringFieldCustom('time_proximity')
                          ? 'text-purple-600 dark:text-purple-400'
                          : 'text-n-slate-10'
                      "
                    >
                      {{
                        isScoringFieldCustom('time_proximity')
                          ? t('PAYMENT_HANDLES.SCORING_FIELD_CUSTOM')
                          : t('PAYMENT_HANDLES.SCORING_FIELD_DEFAULT')
                      }}
                    </span>
                  </div>
                  <span class="text-xs text-n-slate-11">
                    {{ t('PAYMENT_HANDLES.SCORING_TIME_WINDOW') }}:
                  </span>
                  <div class="flex flex-col items-end gap-0.5">
                    <input
                      v-model.number="
                        scoringPlatformDraft.time_proximity_minutes
                      "
                      type="number"
                      min="1"
                      max="1440"
                      :disabled="isPlatformInputsDisabled"
                      class="h-8 w-16 rounded-md border border-n-weak bg-n-alpha-3 px-2 text-sm"
                      :class="
                        isPlatformInputsDisabled
                          ? 'text-n-slate-10 opacity-60'
                          : 'text-n-slate-12'
                      "
                      @input="onScoringInput"
                    />
                    <span
                      v-if="showScoringOverrideIndicators"
                      class="text-[10px] leading-none"
                      :class="
                        isScoringFieldCustom('time_proximity_minutes')
                          ? 'text-purple-600 dark:text-purple-400'
                          : 'text-n-slate-10'
                      "
                    >
                      {{
                        isScoringFieldCustom('time_proximity_minutes')
                          ? t('PAYMENT_HANDLES.SCORING_FIELD_CUSTOM')
                          : t('PAYMENT_HANDLES.SCORING_FIELD_DEFAULT')
                      }}
                    </span>
                  </div>
                  <span class="text-xs text-n-slate-11">
                    {{ t('PAYMENT_HANDLES.SCORING_TIME_MINUTES') }}
                  </span>
                </div>
              </div>
              <div
                class="grid grid-cols-[1fr_5rem] items-center gap-2 px-3 py-2"
              >
                <span
                  class="text-sm"
                  :class="
                    isPlatformInputsDisabled
                      ? 'text-n-slate-10'
                      : 'text-n-slate-12'
                  "
                >
                  {{ t('PAYMENT_HANDLES.SCORING_TIME_MATCH') }}
                </span>
                <div class="flex flex-col items-end gap-0.5">
                  <input
                    v-model.number="scoringPlatformDraft.time_match"
                    type="number"
                    min="0"
                    max="100"
                    :disabled="isPlatformInputsDisabled"
                    class="h-8 w-full rounded-md border border-n-weak bg-n-alpha-3 px-2 text-sm"
                    :class="
                      isPlatformInputsDisabled
                        ? 'text-n-slate-10 opacity-60'
                        : 'text-n-slate-12'
                    "
                    @input="onScoringInput"
                  />
                  <span
                    v-if="showScoringOverrideIndicators"
                    class="text-[10px] leading-none"
                    :class="
                      isScoringFieldCustom('time_match')
                        ? 'text-purple-600 dark:text-purple-400'
                        : 'text-n-slate-10'
                    "
                  >
                    {{
                      isScoringFieldCustom('time_match')
                        ? t('PAYMENT_HANDLES.SCORING_FIELD_CUSTOM')
                        : t('PAYMENT_HANDLES.SCORING_FIELD_DEFAULT')
                    }}
                  </span>
                </div>
              </div>
            </div>
          </div>

          <div>
            <h3
              class="mb-3 text-xs font-semibold uppercase tracking-wide text-n-slate-11"
            >
              {{ t('PAYMENT_HANDLES.SCORING_THRESHOLDS_TITLE') }}
            </h3>
            <div class="overflow-hidden rounded-lg border border-n-weak">
              <div
                class="grid grid-cols-[1fr_5rem] gap-2 border-b border-n-weak bg-n-alpha-2 px-3 py-2 text-[11px] font-medium text-n-slate-11"
              >
                <span>{{ t('PAYMENT_HANDLES.SCORING_THRESHOLDS_TITLE') }}</span>
                <span>{{ t('PAYMENT_HANDLES.SCORING_THRESHOLD') }}</span>
              </div>
              <div
                v-for="field in SCORING_THRESHOLD_FIELDS"
                :key="field.key"
                class="grid grid-cols-[1fr_5rem] items-center gap-2 border-b border-n-weak/70 px-3 py-2 last:border-b-0"
              >
                <span
                  class="text-sm"
                  :class="
                    isPlatformInputsDisabled
                      ? 'text-n-slate-10'
                      : 'text-n-slate-12'
                  "
                >
                  {{ field.prefix }}
                  {{ t(field.labelKey) }}
                </span>
                <div class="flex flex-col items-end gap-0.5">
                  <input
                    v-model.number="scoringPlatformDraft[field.key]"
                    type="number"
                    min="0"
                    max="100"
                    :disabled="isPlatformInputsDisabled"
                    class="h-8 w-full rounded-md border bg-n-alpha-3 px-2 text-sm"
                    :class="[
                      field.inputClass,
                      isPlatformInputsDisabled
                        ? 'text-n-slate-10 opacity-60'
                        : 'text-n-slate-12',
                    ]"
                    @input="onScoringInput"
                  />
                  <span
                    v-if="showScoringOverrideIndicators"
                    class="text-[10px] leading-none"
                    :class="
                      isScoringFieldCustom(field.key)
                        ? 'text-purple-600 dark:text-purple-400'
                        : 'text-n-slate-10'
                    "
                  >
                    {{
                      isScoringFieldCustom(field.key)
                        ? t('PAYMENT_HANDLES.SCORING_FIELD_CUSTOM')
                        : t('PAYMENT_HANDLES.SCORING_FIELD_DEFAULT')
                    }}
                  </span>
                </div>
              </div>
            </div>
          </div>
        </div>

        <div class="mt-6">
          <h3
            class="mb-3 text-xs font-semibold uppercase tracking-wide text-n-slate-11"
          >
            {{ t('PAYMENT_HANDLES.SCORING_CUSTOM_RULES_TITLE') }}
          </h3>
          <div class="overflow-hidden rounded-lg border border-n-weak">
            <div
              v-for="(rule, index) in customRules"
              :key="index"
              class="flex items-center gap-2 border-b border-n-weak/70 px-3 py-2 last:border-b-0"
            >
              <input
                v-model="rule.name"
                type="text"
                :placeholder="
                  t('PAYMENT_HANDLES.SCORING_RULE_NAME_PLACEHOLDER')
                "
                class="h-8 min-w-0 flex-1 rounded-md border border-n-weak bg-n-alpha-3 px-2 text-sm text-n-slate-12"
              />
              <input
                v-model.number="rule.points"
                type="number"
                min="-100"
                max="100"
                class="h-8 w-20 rounded-md border border-n-weak bg-n-alpha-3 px-2 text-sm text-n-slate-12"
              />
              <button
                type="button"
                class="inline-flex size-8 shrink-0 items-center justify-center rounded-md text-n-slate-11 transition-colors hover:bg-n-ruby-2 hover:text-n-ruby-11"
                :aria-label="t('PAYMENT_HANDLES.SCORING_DELETE_RULE')"
                @click="removeCustomRule(index)"
              >
                <span class="i-lucide-trash-2 size-4" />
              </button>
            </div>
            <button
              type="button"
              class="flex w-full items-center gap-2 px-3 py-2.5 text-sm font-medium text-[#6E56CF] transition-colors hover:bg-[#F0EDFF]/40"
              @click="addCustomRule"
            >
              <span class="i-lucide-plus size-4" aria-hidden="true" />
              {{ t('PAYMENT_HANDLES.SCORING_ADD_RULE') }}
            </button>
          </div>
        </div>

        <div class="ph-scoring-save">
          <Button
            :label="t('PAYMENT_HANDLES.SCORING_SAVE')"
            size="sm"
            color="blue"
            :is-loading="scoringSaving"
            @click="saveScoringConfig"
          />
        </div>
      </div>
    </template>

    <template #body>
      <div class="card">
        <div class="card-toolbar">
          <span v-if="handles.length" class="handle-count">
            {{ t('PAYMENT_HANDLES.HANDLE_COUNT', { n: handles.length }) }}
          </span>
          <div class="card-toolbar-actions">
            <button
              type="button"
              class="btn sm"
              :class="{ 'btn-active': scoringSettingsOpen }"
              @click="scoringSettingsOpen = !scoringSettingsOpen"
            >
              {{ t('PAYMENT_HANDLES.SCORING_BUTTON') }}
            </button>
            <button type="button" class="btn primary sm" @click="openCreate">
              {{ t('PAYMENT_HANDLES.ADD_BUTTON') }}
            </button>
          </div>
        </div>

        <table class="tbl">
          <thead>
            <tr>
              <th v-for="header in tableHeaders" :key="header">
                {{ header }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr v-if="!filteredRecords.length">
              <td :colspan="tableHeaders.length" class="tbl-empty">
                {{
                  searchQuery
                    ? t('PAYMENT_HANDLES.NO_RESULTS')
                    : t('PAYMENT_HANDLES.EMPTY')
                }}
              </td>
            </tr>
            <template v-for="row in filteredRecords" :key="row.id">
              <tr>
                <td>
                  <span class="pm-tag">
                    <span
                      class="pm-ic"
                      :style="{
                        background: platformIconMeta(row.platform).bg,
                      }"
                    >
                      {{ platformIconMeta(row.platform).abbr }}
                    </span>
                    {{ platformLabel(row.platform) }}
                  </span>
                </td>
                <td class="fc">{{ row.handle }}</td>
                <td class="ph-display-name">
                  {{ row.display_name || '—' }}
                </td>
                <td class="prio">{{ row.priority }}</td>
                <td>
                  <span :class="statusBadgeClass(row.status)">
                    {{ statusLabel(row.status) }}
                  </span>
                </td>
                <td :class="failCountClass(row.failure_count)">
                  {{ row.failure_count ?? 0 }}
                </td>
                <td class="ph-last-failed">
                  {{ safeDynamicTime(row.last_failure_at) }}
                </td>
                <td>
                  <button
                    type="button"
                    class="ledger"
                    :class="{ 'ledger-open': isLedgerOpen(row.id) }"
                    :title="LEDGER_LABELS.ledgerToggle"
                    @click="toggleLedger(row.id)"
                  >
                    {{ t('PAYMENT_HANDLES.LEDGER_VIEW') }}
                  </button>
                </td>
                <td class="ph-actions">
                  <Button
                    v-tooltip.top="t('PAYMENT_HANDLES.EDIT')"
                    icon="i-woot-edit-pen"
                    slate
                    sm
                    @click="openEdit(row)"
                  />
                  <Button
                    v-tooltip.top="t('PAYMENT_HANDLES.DELETE')"
                    icon="i-woot-bin"
                    slate
                    sm
                    class="ph-delete-btn"
                    @click="openDelete(row)"
                  />
                </td>
              </tr>
              <tr v-if="isLedgerOpen(row.id)" class="ph-ledger-row">
                <td :colspan="tableHeaders.length" class="ph-ledger-cell">
                  <div class="ph-ledger-panel">
                    <div class="ph-ledger-head">
                      <div>
                        <h3 class="ph-ledger-title">
                          {{ LEDGER_LABELS.title }}
                        </h3>
                        <p class="ph-ledger-sub">
                          {{ platformLabel(row.platform) }} · {{ row.handle }}
                        </p>
                      </div>
                      <button
                        type="button"
                        class="btn primary sm"
                        @click="exportLedger(row)"
                      >
                        {{ LEDGER_LABELS.export }}
                      </button>
                    </div>

                    <div v-if="isLedgerLoading(row.id)" class="ph-ledger-state">
                      <span class="ph-ledger-loading">
                        <span class="i-lucide-loader-circle ph-spin" />
                        {{ t('PAYMENT_HANDLES.LOADING') }}
                      </span>
                    </div>

                    <div
                      v-else-if="!getPaymentEvents(row).length"
                      class="ph-ledger-state"
                    >
                      {{ LEDGER_LABELS.empty }}
                    </div>

                    <div v-else class="ph-ledger-events">
                      <article
                        v-for="event in getPaymentEvents(row)"
                        :key="event.id"
                        class="ph-ledger-event"
                        :class="
                          stripColorClass(ledgerStatusSummary(event).color)
                        "
                      >
                        <button
                          type="button"
                          class="ph-ledger-event-head"
                          @click="toggleLedgerRow(event.id)"
                        >
                          <div class="flex min-w-0 flex-1 flex-col gap-1">
                            <div class="flex flex-wrap items-center gap-3">
                              <span
                                class="text-xl font-bold tabular-nums text-n-slate-12"
                              >
                                {{ formatLedgerAmount(event.amount) }}
                              </span>
                              <span
                                class="inline-flex items-center rounded-full border px-2.5 py-0.5 text-xs font-medium capitalize"
                                :class="platformBadgeClass(event.platform)"
                              >
                                {{ platformLabel(event.platform) }}
                              </span>
                              <div
                                class="relative group flex items-center gap-2 min-w-[100px]"
                              >
                                <span
                                  class="text-[11px] font-medium text-n-slate-11"
                                >
                                  {{ LEDGER_LABELS.score }}
                                </span>
                                <div
                                  class="h-1.5 w-16 overflow-hidden rounded-full bg-n-slate-4"
                                >
                                  <div
                                    v-if="event.score != null"
                                    class="h-full rounded-full"
                                    :class="scoreBarClass(event.score)"
                                    :style="{ width: `${event.score}%` }"
                                  />
                                </div>
                                <span
                                  class="text-xs font-semibold tabular-nums"
                                  :class="scoreTextClass(event.score)"
                                >
                                  {{ event.score ?? '—' }}
                                </span>
                                <div
                                  v-if="event.score_breakdown"
                                  class="absolute z-10 hidden group-hover:block right-0 top-full mt-1 w-56 rounded-lg border border-n-weak bg-n-solid-1 p-3 shadow-lg text-xs"
                                >
                                  <div class="font-semibold mb-2">
                                    {{ LEDGER_LABELS.scoreBreakdown }}
                                  </div>
                                  <div
                                    v-for="breakdownRow in getScoreBreakdownRows(
                                      event.score_breakdown
                                    )"
                                    :key="breakdownRow.key"
                                    class="flex justify-between mb-1 last:mb-0"
                                  >
                                    <span>{{ breakdownRow.label }}</span>
                                    <span
                                      :class="
                                        breakdownRow.earned > 0
                                          ? 'text-green-600 font-semibold'
                                          : 'text-n-slate-10'
                                      "
                                    >
                                      {{ breakdownRow.display }}
                                    </span>
                                  </div>
                                </div>
                              </div>
                              <span
                                class="inline-flex items-center rounded-full px-2.5 py-0.5 text-[11px] font-medium"
                                :class="
                                  stripBadgeClass(
                                    ledgerStatusSummary(event).color
                                  )
                                "
                              >
                                {{ ledgerStatusSummary(event).label }}
                              </span>
                            </div>
                            <p
                              v-if="ledgerStatusSummary(event).reason"
                              class="m-0 truncate text-xs text-n-slate-11"
                            >
                              {{ ledgerStatusSummary(event).reason }}
                            </p>
                          </div>
                          <span
                            class="shrink-0 pt-1 text-n-slate-11"
                            aria-hidden="true"
                          >
                            {{ isLedgerRowExpanded(event.id) ? '▾' : '▸' }}
                          </span>
                        </button>

                        <div v-show="isLedgerRowExpanded(event.id)">
                          <!-- Screenshot row -->
                          <div
                            class="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1 border-b border-[#DDD8F5]/70 bg-[#F0EDFF]/20 px-4 py-3 text-xs dark:bg-[#6E56CF]/5"
                          >
                            <button
                              type="button"
                              class="col-span-2 mb-1 inline-flex w-fit items-center rounded-full border border-[#6E56CF]/30 bg-[#F0EDFF] px-2.5 py-0.5 text-[11px] font-medium text-[#4C3799] transition-colors hover:border-[#6E56CF] hover:bg-[#6E56CF]/10 disabled:cursor-not-allowed disabled:opacity-50"
                              :disabled="!event.screenshot.imageUrl"
                              @click="
                                openScreenshotModal(event.screenshot.imageUrl)
                              "
                            >
                              {{ LEDGER_LABELS.sourceScreenshot }}
                            </button>
                            <span class="text-n-slate-11">{{
                              LEDGER_LABELS.sender
                            }}</span>
                            <span class="font-medium text-n-slate-12">
                              {{ event.screenshot.sender }}
                            </span>
                            <span class="text-n-slate-11">{{
                              LEDGER_LABELS.txnId
                            }}</span>
                            <span class="font-mono text-n-slate-11">
                              {{ event.screenshot.txnId }}
                            </span>
                            <span class="text-n-slate-11">{{
                              LEDGER_LABELS.dateTime
                            }}</span>
                            <span class="text-n-slate-11">{{
                              event.screenshot.time
                            }}</span>
                            <span class="text-n-slate-11">{{
                              LEDGER_LABELS.note
                            }}</span>
                            <span class="text-n-slate-11">{{
                              event.screenshot.note
                            }}</span>
                          </div>

                          <!-- Email row -->
                          <div
                            v-if="hasEmailRowData(event)"
                            class="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1 px-4 py-3 text-xs bg-[#E6F7F2]/20 dark:bg-[#0F9B76]/5"
                          >
                            <button
                              type="button"
                              class="col-span-2 mb-1 inline-flex w-fit items-center rounded-full border border-[#0F9B76]/30 bg-[#E6F7F2] px-2.5 py-0.5 text-[11px] font-medium text-[#0F9B76] transition-colors hover:border-[#0F9B76] hover:bg-[#0F9B76]/10"
                              @click="openEmailModal(event)"
                            >
                              {{ LEDGER_LABELS.sourceEmail }}
                            </button>
                            <span class="text-n-slate-11">{{
                              LEDGER_LABELS.sender
                            }}</span>
                            <span class="font-medium text-n-slate-12">
                              {{ event.email.sender }}
                              <span
                                v-if="emailSenderMatches(event)"
                                class="ml-1 text-green-600"
                              >
                                {{ LEDGER_LABELS.matchCheck }}
                              </span>
                            </span>
                            <span class="text-n-slate-11">{{
                              LEDGER_LABELS.emailSubject
                            }}</span>
                            <span class="text-n-slate-11">{{
                              event.email.subject
                            }}</span>
                            <span class="text-n-slate-11">{{
                              LEDGER_LABELS.dateTime
                            }}</span>
                            <span class="text-n-slate-11">
                              {{ event.email.date }}
                              <span
                                v-if="emailDateMatches(event)"
                                class="ml-1 text-green-600"
                              >
                                {{ LEDGER_LABELS.matchCheck }}
                              </span>
                            </span>
                            <span class="text-n-slate-11">{{
                              LEDGER_LABELS.note
                            }}</span>
                            <span class="text-n-slate-11">
                              {{ event.email.note }}
                              <span
                                v-if="emailAmountMatches(event)"
                                class="ml-1 text-green-600"
                              >
                                {{ LEDGER_LABELS.matchCheck }}
                              </span>
                            </span>
                          </div>
                          <div
                            v-else
                            class="px-4 py-3 text-xs text-n-slate-11 bg-n-alpha-2"
                          >
                            {{ LEDGER_LABELS.awaitingEmail }}
                          </div>
                        </div>
                      </article>
                    </div>
                  </div>
                </td>
              </tr>
            </template>
          </tbody>
        </table>
      </div>
    </template>

    <woot-modal v-model:show="showFormModal" :on-close="hideFormModal">
      <div class="flex flex-col h-auto overflow-auto">
        <woot-modal-header
          :header-title="
            formMode === 'create'
              ? t('PAYMENT_HANDLES.MODAL.ADD_TITLE')
              : t('PAYMENT_HANDLES.MODAL.EDIT_TITLE')
          "
          :header-content="
            formMode === 'create'
              ? t('PAYMENT_HANDLES.MODAL.ADD_DESC')
              : t('PAYMENT_HANDLES.MODAL.EDIT_DESC')
          "
        />
        <form
          class="flex flex-col gap-4 px-0 pb-2"
          @submit.prevent="submitForm"
        >
          <div
            v-if="formErrors.length"
            class="p-3 text-sm rounded-lg border text-n-ruby-11 bg-n-ruby-2 border-n-ruby-7"
            role="alert"
          >
            <p class="m-0 mb-1 font-medium">
              {{ t('PAYMENT_HANDLES.VALIDATION_ERROR_PREFIX') }}
            </p>
            <ul class="pl-4 m-0 list-disc">
              <li v-for="(err, idx) in formErrors" :key="idx">
                {{ err }}
              </li>
            </ul>
          </div>

          <div class="grid gap-4 sm:grid-cols-2">
            <label class="flex flex-col gap-1 text-sm">
              <span class="text-n-slate-11">{{
                t('PAYMENT_HANDLES.FORM.PLATFORM')
              }}</span>
              <select
                v-model="form.platform"
                :disabled="formMode === 'edit'"
                class="h-10 px-3 text-sm rounded-lg border bg-n-alpha-3 border-n-weak text-n-slate-12"
              >
                <option v-for="p in PLATFORMS" :key="p" :value="p">
                  {{ platformLabel(p) }}
                </option>
              </select>
            </label>
            <label class="flex flex-col gap-1 text-sm">
              <span class="text-n-slate-11">{{
                t('PAYMENT_HANDLES.FORM.STATUS')
              }}</span>
              <select
                v-model="form.status"
                class="h-10 px-3 text-sm rounded-lg border bg-n-alpha-3 border-n-weak text-n-slate-12"
              >
                <option v-for="s in STATUSES" :key="s" :value="s">
                  {{ statusLabel(s) }}
                </option>
              </select>
            </label>
          </div>

          <woot-input
            v-model="form.handle"
            class="w-full"
            :label="t('PAYMENT_HANDLES.FORM.HANDLE')"
            :placeholder="t('PAYMENT_HANDLES.FORM.HANDLE_PLACEHOLDER')"
            data-testid="payment-handle-handle"
          />
          <woot-input
            v-model="form.display_name"
            class="w-full"
            :label="t('PAYMENT_HANDLES.FORM.DISPLAY_NAME')"
            :placeholder="t('PAYMENT_HANDLES.FORM.DISPLAY_NAME_PLACEHOLDER')"
            data-testid="payment-handle-display-name"
          />
          <woot-input
            v-model.number="form.priority"
            class="w-full"
            type="number"
            :label="t('PAYMENT_HANDLES.FORM.PRIORITY')"
            data-testid="payment-handle-priority"
          />

          <label class="flex flex-col gap-1 text-sm">
            <span class="text-n-slate-11">{{
              t('PAYMENT_HANDLES.FORM.NOTES')
            }}</span>
            <textarea
              v-model="form.notes"
              rows="3"
              class="px-3 py-2 text-sm rounded-lg border resize-y bg-n-alpha-3 border-n-weak text-n-slate-12"
            />
          </label>

          <button
            type="button"
            class="flex gap-2 items-center px-0 py-2 text-sm font-medium text-left border-0 bg-transparent text-woot-500"
            @click="emailSectionOpen = !emailSectionOpen"
          >
            <span
              class="transition-transform i-lucide-chevron-down size-4"
              :class="{ 'rotate-180': emailSectionOpen }"
            />
            {{ t('PAYMENT_HANDLES.FORM.VERIFICATION_SECTION') }}
          </button>
          <div
            v-show="emailSectionOpen"
            class="grid gap-4 p-4 rounded-xl border border-n-weak bg-n-alpha-2"
          >
            <woot-input
              v-model="form.verification_email"
              class="w-full"
              type="email"
              :label="t('PAYMENT_HANDLES.FORM.VERIFICATION_EMAIL')"
              placeholder="your.account@gmail.com (host auto-fills)"
            />
            <woot-input
              v-model="form.verification_email_password"
              class="w-full"
              type="password"
              autocomplete="new-password"
              :label="t('PAYMENT_HANDLES.FORM.VERIFICATION_PASSWORD')"
              :placeholder="
                formMode === 'edit'
                  ? t('PAYMENT_HANDLES.FORM.PASSWORD_PLACEHOLDER')
                  : ''
              "
            />
            <div class="grid gap-4 sm:grid-cols-2">
              <div class="flex flex-col gap-1">
                <woot-input
                  v-model="form.verification_email_host"
                  class="w-full"
                  :label="t('PAYMENT_HANDLES.FORM.VERIFICATION_HOST')"
                />
                <p class="m-0 text-xs text-n-slate-11">
                  {{ IMAP_HOST_HINT }}
                </p>
              </div>
              <woot-input
                v-model.number="form.verification_email_port"
                class="w-full"
                type="number"
                :label="t('PAYMENT_HANDLES.FORM.VERIFICATION_PORT')"
              />
            </div>
            <label
              class="inline-flex gap-2 items-center text-sm cursor-pointer select-none"
            >
              <input
                v-model="form.verification_email_ssl"
                type="checkbox"
                class="rounded border-n-weak"
              />
              <span>{{ t('PAYMENT_HANDLES.FORM.VERIFICATION_SSL') }}</span>
            </label>
          </div>

          <div class="flex gap-2 justify-end pt-2">
            <Button
              faded
              slate
              type="button"
              :label="t('PAYMENT_HANDLES.CANCEL')"
              @click="hideFormModal"
            />
            <Button
              type="submit"
              color="blue"
              :label="t('PAYMENT_HANDLES.SAVE')"
              :is-loading="formSubmitting"
            />
          </div>
        </form>
      </div>
    </woot-modal>

    <woot-delete-modal
      v-model:show="showDeleteModal"
      :on-close="closeDelete"
      :on-confirm="confirmDelete"
      :title="t('PAYMENT_HANDLES.DELETE_CONFIRM.TITLE')"
      :message="t('PAYMENT_HANDLES.DELETE_CONFIRM.MESSAGE')"
      :message-value="deleteMessage"
      :confirm-text="t('PAYMENT_HANDLES.DELETE_CONFIRM.YES')"
      :reject-text="t('PAYMENT_HANDLES.DELETE_CONFIRM.NO')"
    />

    <woot-modal
      v-model:show="showScreenshotModal"
      :on-close="closeScreenshotModal"
    >
      <div class="p-4">
        <img
          v-if="modalImageUrl"
          :src="modalImageUrl"
          :alt="LEDGER_LABELS.screenshotPlaceholder"
          class="max-h-[70vh] w-full rounded-lg object-contain"
        />
      </div>
    </woot-modal>

    <woot-modal v-model:show="showEmailModal" :on-close="closeEmailModal">
      <div class="flex flex-col gap-3 p-4 text-sm">
        <div>
          <span class="text-n-slate-11">{{ LEDGER_LABELS.emailFrom }}: </span>
          <span class="text-n-slate-12">{{
            modalEmailContent.from || '—'
          }}</span>
        </div>
        <div>
          <span class="text-n-slate-11">
            {{ LEDGER_LABELS.emailSubject }}:
          </span>
          <span class="text-n-slate-12">{{
            modalEmailContent.subject || '—'
          }}</span>
        </div>
        <div>
          <span class="text-n-slate-11">{{ LEDGER_LABELS.dateTime }}: </span>
          <span class="text-n-slate-12">{{
            modalEmailContent.date || '—'
          }}</span>
        </div>
        <pre
          class="m-0 max-h-64 overflow-auto rounded-lg border border-n-weak bg-n-alpha-2 p-3 text-xs leading-relaxed text-n-slate-12 whitespace-pre-wrap"
        >
          {{ modalEmailContent.body || '—' }}
        </pre>
      </div>
    </woot-modal>
  </SettingsLayout>
</template>

<style scoped>
.pat-ph-wrap {
  --canvas: #050409;
  --surface: #0c0b12;
  --surface-2: #131119;
  --surface-3: #1b1925;
  --surface-4: #252233;
  --border: #171520;
  --border-hi: #2e2940;
  --patra: #6e56cf;
  --patra-2: #8b5cf6;
  --patra-3: #a78bfa;
  --patra-deep: #5b45b0;
  --patra-glow: rgba(110, 86, 207, 0.55);
  --text: #ededf2;
  --text-2: #a8a6b6;
  --text-3: #75727f;
  --text-4: #54515e;
  --green: #3fb950;
  --amber: #d29922;
  --red: #f85149;

  color: var(--text);
}

.pat-ph-wrap :deep(h1) {
  font-family: 'Space Grotesk', sans-serif;
  color: var(--text);
}

.pat-ph-wrap :deep(.text-n-slate-11),
.pat-ph-wrap :deep(.text-body-main) {
  color: var(--text-2);
}

.card {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 14px;
  padding: 18px 20px;
  box-shadow: 0 4px 24px rgba(0, 0, 0, 0.35);
}

.card-toolbar {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 14px;
  gap: 12px;
  flex-wrap: wrap;
}

.handle-count {
  font-size: 12px;
  color: var(--text-3);
}

.card-toolbar-actions {
  display: flex;
  gap: 9px;
  flex-wrap: wrap;
}

.btn {
  font-size: 12.5px;
  font-weight: 500;
  padding: 8px 14px;
  border-radius: 9px;
  border: 1px solid var(--border-hi);
  background: var(--surface-3);
  color: var(--text-2);
  cursor: pointer;
  transition: all 0.2s;
}

.btn:hover {
  border-color: var(--patra);
  color: var(--patra-3);
}

.btn.primary {
  background: linear-gradient(135deg, var(--patra), var(--patra-deep));
  border-color: transparent;
  color: #fff;
  box-shadow: 0 3px 10px var(--patra-glow);
}

.btn.primary:hover {
  filter: brightness(1.08);
  color: #fff;
}

.btn.sm {
  padding: 6px 12px;
  font-size: 12px;
}

.btn-active {
  border-color: var(--patra);
  color: var(--patra-3);
  background: rgba(110, 86, 207, 0.14);
}

.tbl {
  width: 100%;
  border-collapse: collapse;
}

.tbl th {
  font-size: 11px;
  color: var(--text-4);
  text-transform: uppercase;
  letter-spacing: 0.04em;
  font-family: 'JetBrains Mono', monospace;
  text-align: left;
  padding: 9px 10px;
  border-bottom: 1px solid var(--border);
  font-weight: 600;
}

.tbl td {
  font-size: 13px;
  padding: 12px 10px;
  border-bottom: 1px solid var(--border);
  color: var(--text);
  vertical-align: middle;
}

.tbl tbody tr:last-child td,
.tbl tbody tr.ph-ledger-row td {
  border-bottom: none;
}

.tbl tbody tr:not(.ph-ledger-row) {
  transition: background 0.2s;
}

.tbl tbody tr:not(.ph-ledger-row):hover {
  background: var(--surface-2);
}

.tbl-empty {
  text-align: center;
  color: var(--text-3);
  padding: 28px 10px !important;
}

.pm-tag {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  font-weight: 600;
}

.pm-ic {
  width: 24px;
  height: 16px;
  border-radius: 4px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  font-size: 8px;
  font-weight: 700;
  color: #fff;
  flex-shrink: 0;
}

.st-active {
  font-size: 11px;
  font-weight: 600;
  color: var(--green);
  background: rgba(63, 185, 80, 0.16);
  padding: 3px 9px;
  border-radius: 20px;
}

.st-failed {
  font-size: 11px;
  font-weight: 600;
  color: var(--red);
  background: rgba(248, 81, 73, 0.16);
  padding: 3px 9px;
  border-radius: 20px;
}

.st-disabled {
  font-size: 11px;
  font-weight: 600;
  color: var(--text-3);
  background: var(--surface-4);
  padding: 3px 9px;
  border-radius: 20px;
}

.prio {
  font-family: 'JetBrains Mono', monospace;
  font-weight: 600;
  color: var(--patra-3);
}

.fc {
  font-family: 'JetBrains Mono', monospace;
}

.fc.bad {
  color: var(--amber);
}

.ledger {
  font-size: 11px;
  color: var(--patra-3);
  cursor: pointer;
  background: none;
  border: none;
  padding: 0;
  font-family: inherit;
}

.ledger:hover {
  text-decoration: underline;
}

.ledger-open {
  font-weight: 600;
  text-decoration: underline;
}

.ph-display-name,
.ph-last-failed {
  color: var(--text-2);
  font-size: 12px;
}

.ph-actions {
  display: flex;
  justify-content: flex-end;
  align-items: center;
  gap: 6px;
  white-space: nowrap;
}

.ph-delete-btn:hover:enabled {
  color: var(--red) !important;
}

.ph-scoring-panel {
  margin-top: 12px;
  margin-bottom: 16px;
  padding: 16px 18px;
  border-radius: 14px;
  border: 1px solid var(--border);
  background: var(--surface);
}

.ph-scoring-panel :deep(.border-\\[\\#DDD8F5\\]),
.ph-scoring-panel :deep(.border-n-weak) {
  border-color: var(--border) !important;
}

.ph-scoring-panel :deep(.bg-\\[\\#F0EDFF\\]\\/60),
.ph-scoring-panel :deep(.bg-n-alpha-2) {
  background: rgba(110, 86, 207, 0.12) !important;
}

.ph-scoring-panel :deep(.text-\\[\\#4C3799\\]),
.ph-scoring-panel :deep(.text-n-slate-12) {
  color: var(--text) !important;
}

.ph-scoring-panel :deep(input) {
  background: var(--canvas);
  border-color: var(--border);
  color: var(--text);
}

.ph-scoring-save {
  margin-top: 16px;
  display: flex;
  justify-content: flex-end;
}

.ph-ledger-cell {
  padding: 0 !important;
  background: var(--surface-2);
}

.ph-ledger-panel {
  padding: 16px 18px;
}

.ph-ledger-head {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  margin-bottom: 14px;
}

.ph-ledger-title {
  margin: 0;
  font-size: 14px;
  font-weight: 600;
  color: var(--patra-3);
}

.ph-ledger-sub {
  margin: 4px 0 0;
  font-size: 11px;
  color: var(--text-3);
}

.ph-ledger-state {
  border: 1px solid var(--border);
  border-radius: 10px;
  background: var(--surface);
  padding: 24px 16px;
  text-align: center;
  font-size: 13px;
  color: var(--text-3);
}

.ph-ledger-loading {
  display: inline-flex;
  align-items: center;
  gap: 8px;
}

.ph-spin {
  width: 16px;
  height: 16px;
  animation: ph-spin 0.8s linear infinite;
  color: var(--patra-3);
}

@keyframes ph-spin {
  to {
    transform: rotate(360deg);
  }
}

.ph-ledger-events {
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.ph-ledger-event {
  overflow: hidden;
  border-radius: 12px;
  border: 1px solid var(--border);
  background: var(--surface);
  border-left-width: 4px;
}

.ph-ledger-event-head {
  display: flex;
  width: 100%;
  align-items: flex-start;
  justify-content: space-between;
  gap: 12px;
  border: none;
  border-bottom: 1px solid var(--border);
  background: var(--surface-3);
  padding: 12px 14px;
  text-align: left;
  cursor: pointer;
  color: var(--text);
  transition: background 0.2s;
}

.ph-ledger-event-head:hover {
  background: var(--surface-4);
}

.ph-ledger-event :deep(.text-n-slate-12) {
  color: var(--text);
}

.ph-ledger-event :deep(.text-n-slate-11) {
  color: var(--text-3);
}
</style>
