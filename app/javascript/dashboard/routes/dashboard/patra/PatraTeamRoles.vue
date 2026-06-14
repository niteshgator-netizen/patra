<script setup>
import { ref, computed, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import AgentsAPI from 'dashboard/api/agents';
import PatraTeamAPI from 'dashboard/api/patraTeam';
import MainFeatureGrantsAPI from 'dashboard/api/mainFeatureGrants';
import InboxMembersAPI from 'dashboard/api/inboxMembers';

const showAlert = useAlert;
const store = useStore();

// ── the six canonical tiers (mirrors CustomRoleTemplates::TIERS) ──
const TIERS = [
  { key: 'owner', label: 'Owner', locked: true, badge: 'owner' },
  { key: 'admin', label: 'Admin', badge: 'admin' },
  { key: 'manager', label: 'Manager', badge: 'manager' },
  { key: 'cashier', label: 'Cashier', badge: 'cashier' },
  { key: 'agent', label: 'Agent', badge: 'agent' },
  { key: 'viewer', label: 'Viewer', badge: 'viewer' },
];

// grouped permission toggles over the full custom-role vocabulary (contact_pii_* handled separately)
const PERMISSION_GROUPS = [
  {
    label: 'Conversations',
    keys: [
      'conversation_manage',
      'conversation_unassigned_manage',
      'conversation_participating_manage',
      'bulk_reassign',
    ],
  },
  { label: 'Contacts', keys: ['contact_manage'] },
  { label: 'Reports', keys: ['report_view', 'report_manage'] },
  {
    label: 'Team & Settings',
    keys: [
      'team_manage',
      'settings_manage',
      'integrations_manage',
      'knowledge_base_manage',
    ],
  },
  {
    label: 'Money',
    keys: ['money_action_manage', 'cashout_approve', 'message_edit_delete'],
  },
  {
    label: 'Channels',
    keys: [
      'view_all_inboxes',
      'facebook_connect_manage',
      'channel_link_manage',
      'backup_page_manage',
      'game_credentials_manage',
      'payment_handle_manage',
      'broadcast_send',
      'incident_pause_ai',
      'secrets_manage',
    ],
  },
];

// Granted main features = the real grantable MAIN_FEATURES, minus billing (owner-only).
const GRANTED_MAINS = [
  { key: 'facebook_connections', label: 'Facebook connect' },
  { key: 'game_credentials', label: 'Game credentials' },
  { key: 'payment_handles', label: 'Payment handles' },
  { key: 'backup_pages', label: 'Backup pages' },
  { key: 'secrets', label: 'Secrets' },
];

const PRIVACY_STATES = [
  { key: 'contact_pii_full', label: 'Full name', sample: 'Jordan Mitchell' },
  { key: 'contact_pii_first_name', label: 'First name only', sample: 'Jordan' },
  { key: 'contact_pii_hidden', label: 'Hidden', sample: 'Player' },
];
const PRIVACY_KEYS = PRIVACY_STATES.map(s => s.key);

const labelFor = key =>
  key
    .replace(/_/g, ' ')
    .replace(/\bmanage\b/, '')
    .trim()
    .replace(/^\w/, c => c.toUpperCase());

// ── state ──
const members = useMapGetter('agents/getAgents');
const customRoles = useMapGetter('customRole/getCustomRoles');
const currentUser = useMapGetter('getCurrentUser');
const inboxes = useMapGetter('inboxes/getInboxes');

const seats = ref({ used: 0, cap: 50, remaining: 50 });
const capDraft = ref(50);
const savingCap = ref(false);
const loading = ref(true);
const selectedId = ref(null);
const inviteEmail = ref('');
const inviting = ref(false);
const savingPerms = ref(false);
const grants = ref([]);
const savingGrants = ref(false);
const memberInboxIds = ref([]);

// working copy of the selected member's role permissions (incl. the privacy key)
const draftPermissions = ref([]);

const selectedMember = computed(
  () => members.value.find(m => m.id === selectedId.value) || null
);

function customRoleOf(member) {
  if (!member) return null;
  const id = member.custom_role_id || member.custom_role?.id;
  if (!id) return null;
  return customRoles.value.find(r => r.id === id) || member.custom_role || null;
}

function tierOf(member) {
  if (!member) return 'agent';
  const role = customRoleOf(member);
  if (role) {
    const name = (role.name || '').toLowerCase();
    if (name.includes('manager')) return 'manager';
    if (name.includes('cashier')) return 'cashier';
    if (name.includes('viewer')) return 'viewer';
    return 'manager';
  }
  if (member.role === 'administrator') {
    return member.id === currentUser.value?.id ? 'owner' : 'admin';
  }
  return 'agent';
}

const tierMeta = key => TIERS.find(t => t.key === key) || TIERS[4];

const isOwnerViewer = computed(
  () => currentUser.value?.role === 'administrator'
);

const selectedPrivacy = computed(
  () =>
    PRIVACY_KEYS.find(k => draftPermissions.value.includes(k)) ||
    'contact_pii_first_name'
);
const privacyPreview = computed(
  () =>
    PRIVACY_STATES.find(s => s.key === selectedPrivacy.value)?.sample ||
    'Jordan'
);

function accountUserId(member) {
  // the membership id (AccountUser) for the current account; defensive across serializer shapes
  return (
    member?.account_user_id ||
    member?.account_user?.id ||
    member?.accounts?.find(a => a.id === store.getters.getCurrentAccountId)
      ?.account_user_id ||
    null
  );
}

async function loadSeats() {
  try {
    const res = await PatraTeamAPI.seats();
    seats.value = res.data || seats.value;
    capDraft.value = seats.value.cap;
  } catch {
    // seats are non-critical chrome; leave defaults
  }
}

async function saveCap() {
  const cap = parseInt(capDraft.value, 10);
  if (!Number.isInteger(cap) || cap < 1) {
    showAlert('Enter a member cap of 1 or more');
    return;
  }
  savingCap.value = true;
  try {
    await PatraTeamAPI.setMemberCap(cap);
    await loadSeats();
    showAlert(`Member cap set to ${cap}`);
  } catch {
    showAlert('Failed to update member cap');
  } finally {
    savingCap.value = false;
  }
}

async function loadGrants(member) {
  grants.value = [];
  const auId = accountUserId(member);
  if (!auId) return;
  try {
    const res = await MainFeatureGrantsAPI.show(auId);
    grants.value = res.data?.granted_main_features || [];
  } catch {
    // owner-only; non-owners simply won't see grants
  }
}

function selectMember(member) {
  selectedId.value = member.id;
  const role = customRoleOf(member);
  draftPermissions.value = [...(role?.permissions || [])];
  if (!PRIVACY_KEYS.some(k => draftPermissions.value.includes(k))) {
    draftPermissions.value.push('contact_pii_first_name');
  }
  memberInboxIds.value = (inboxes.value || [])
    .filter(ibox => (ibox.members || []).some(u => u.id === member.id))
    .map(ibox => ibox.id);
  if (isOwnerViewer.value) loadGrants(member);
}

async function invite() {
  const email = inviteEmail.value.trim();
  if (!email) return;
  if (seats.value.remaining <= 0) {
    showAlert(
      `Seat cap reached (${seats.value.cap}). Remove a member to invite more.`
    );
    return;
  }
  inviting.value = true;
  try {
    await AgentsAPI.bulkInvite({ emails: [email] });
    showAlert(`Invited ${email}`);
    inviteEmail.value = '';
    await Promise.all([store.dispatch('agents/get'), loadSeats()]);
  } catch {
    showAlert('Failed to invite member');
  } finally {
    inviting.value = false;
  }
}

async function assignTier(member, tier) {
  if (tier.locked) return;
  const payload = { id: member.id };
  if (tier.key === 'admin' || tier.key === 'agent') {
    payload.role = tier.key === 'admin' ? 'administrator' : 'agent';
    payload.custom_role_id = null;
  } else {
    const role = customRoles.value.find(r =>
      (r.name || '').toLowerCase().includes(tier.key)
    );
    if (!role) {
      showAlert(
        `No "${tier.label}" custom role exists yet — create it in Custom Roles first.`
      );
      return;
    }
    payload.role = 'agent';
    payload.custom_role_id = role.id;
  }
  try {
    await store.dispatch('agents/update', payload);
    showAlert(`${member.name} is now ${tier.label}`);
    await store.dispatch('agents/get');
    selectMember(members.value.find(m => m.id === member.id) || member);
  } catch {
    showAlert('Failed to change role');
  }
}

function hasPermission(key) {
  return draftPermissions.value.includes(key);
}

function togglePermission(key) {
  const i = draftPermissions.value.indexOf(key);
  if (i >= 0) draftPermissions.value.splice(i, 1);
  else draftPermissions.value.push(key);
}

function setPrivacy(key) {
  draftPermissions.value = draftPermissions.value.filter(
    k => !PRIVACY_KEYS.includes(k)
  );
  draftPermissions.value.push(key);
}

async function savePermissions() {
  const role = customRoleOf(selectedMember.value);
  if (!role) {
    showAlert(
      'This tier has no editable custom role. Assign Manager/Cashier/Viewer first.'
    );
    return;
  }
  savingPerms.value = true;
  try {
    await store.dispatch('customRole/updateCustomRole', {
      id: role.id,
      name: role.name,
      description: role.description,
      permissions: draftPermissions.value,
    });
    showAlert('Permissions saved for this role');
  } catch {
    showAlert('Failed to save permissions');
  } finally {
    savingPerms.value = false;
  }
}

async function toggleGrant(key) {
  const auId = accountUserId(selectedMember.value);
  if (!auId) {
    showAlert('Cannot resolve this member’s membership id.');
    return;
  }
  const next = grants.value.includes(key)
    ? grants.value.filter(g => g !== key)
    : [...grants.value, key];
  savingGrants.value = true;
  try {
    const res = await MainFeatureGrantsAPI.update(auId, next);
    grants.value = res.data?.granted_main_features || next;
    showAlert('Granted features updated');
  } catch {
    showAlert('Failed to update grants (owner only)');
  } finally {
    savingGrants.value = false;
  }
}

async function toggleInbox(ibox) {
  const member = selectedMember.value;
  if (!member) return;
  const current = (ibox.members || []).map(u => u.id);
  const has = memberInboxIds.value.includes(ibox.id);
  const next = has
    ? current.filter(id => id !== member.id)
    : [...new Set([...current, member.id])];
  try {
    await InboxMembersAPI.update({ inboxId: ibox.id, agentList: next });
    memberInboxIds.value = has
      ? memberInboxIds.value.filter(id => id !== ibox.id)
      : [...memberInboxIds.value, ibox.id];
    showAlert('Channel access updated');
  } catch {
    showAlert('Failed to update channel access');
  }
}

onMounted(async () => {
  loading.value = true;
  try {
    await Promise.all([
      store.dispatch('agents/get'),
      store.dispatch('customRole/getCustomRole'),
      store.dispatch('inboxes/get'),
      loadSeats(),
    ]);
    if (members.value.length) selectMember(members.value[0]);
  } catch {
    showAlert('Failed to load team');
  } finally {
    loading.value = false;
  }
});

const seatsLabel = computed(
  () => `${seats.value.used} / ${seats.value.cap} seats`
);

function badgeLabel(member) {
  const meta = tierMeta(tierOf(member));
  return `${meta.locked ? '🔒 ' : ''}${meta.label}`;
}

const selectedTierLabel = computed(() =>
  selectedMember.value ? tierMeta(tierOf(selectedMember.value)).label : ''
);
</script>

<template>
  <div class="flex flex-col gap-5 p-6">
    <header class="flex items-start justify-between gap-4 flex-wrap">
      <div>
        <h2 class="text-2xl font-semibold text-n-slate-12">Team &amp; Roles</h2>
        <p class="text-sm text-n-slate-11">
          Manage who's on your team and exactly what they can do.
        </p>
      </div>
      <div class="flex items-center gap-3">
        <span
          class="mono text-xs px-3 py-1.5 rounded-full bg-n-alpha-2 text-n-slate-11"
        >
          {{ seatsLabel }}
        </span>
        <div v-if="isOwnerViewer" class="flex items-center gap-1">
          <input
            v-model.number="capDraft"
            type="number"
            min="1"
            aria-label="Member cap"
            class="w-16 p-1.5 rounded-lg bg-n-alpha-2 border border-n-weak text-xs text-n-slate-12"
            @keyup.enter="saveCap"
          />
          <button
            type="button"
            :disabled="savingCap"
            class="px-2 py-1.5 rounded-lg border border-n-weak text-xs text-n-slate-11 disabled:opacity-50"
            @click="saveCap"
          >
            {{ savingCap ? '…' : 'Set cap' }}
          </button>
        </div>
        <form class="flex items-center gap-2" @submit.prevent="invite">
          <input
            v-model="inviteEmail"
            type="email"
            placeholder="teammate@email.com"
            class="p-2 rounded-lg bg-n-alpha-2 border border-n-weak text-sm text-n-slate-12 w-52"
          />
          <button
            type="submit"
            :disabled="inviting || seats.remaining <= 0"
            class="px-3 py-2 rounded-lg bg-patra text-white text-sm font-medium disabled:opacity-50"
          >
            {{ inviting ? 'Inviting…' : 'Invite' }}
          </button>
        </form>
      </div>
    </header>

    <div v-if="loading" class="text-sm text-n-slate-11">Loading team…</div>

    <div v-else class="flex flex-col lg:flex-row gap-5">
      <!-- LIST COLUMN -->
      <aside
        class="lg:w-80 shrink-0 rounded-xl border border-n-weak bg-n-solid-1 p-2 flex flex-col gap-1"
      >
        <button
          v-for="member in members"
          :key="member.id"
          type="button"
          class="flex items-center gap-3 p-2 rounded-lg text-left transition-colors"
          :class="
            member.id === selectedId ? 'bg-n-alpha-2' : 'hover:bg-n-alpha-1'
          "
          @click="selectMember(member)"
        >
          <div class="relative shrink-0">
            <div
              class="w-8 h-8 rounded-full bg-patra/20 text-patra grid place-items-center text-xs font-semibold uppercase"
            >
              {{ (member.name || '?').slice(0, 2) }}
            </div>
            <span
              class="absolute -bottom-0.5 -right-0.5 w-2.5 h-2.5 rounded-full border-2 border-n-solid-1"
              :class="
                member.availability_status === 'online'
                  ? 'bg-n-teal-9'
                  : 'bg-n-slate-6'
              "
            />
          </div>
          <div class="min-w-0 grow">
            <div class="text-sm text-n-slate-12 truncate">
              {{ member.name }}
            </div>
            <div class="text-[11px] text-n-slate-10 truncate">
              {{ member.email }}
            </div>
          </div>
          <span class="role-badge" :class="`rb-${tierOf(member)}`">
            {{ badgeLabel(member) }}
          </span>
        </button>
      </aside>

      <!-- DETAIL COLUMN -->
      <section v-if="selectedMember" class="grow flex flex-col gap-5 min-w-0">
        <div class="rounded-xl border border-n-weak bg-n-solid-1 p-4">
          <div class="flex items-center justify-between flex-wrap gap-2">
            <h3 class="text-base font-semibold text-n-slate-12">
              {{ selectedMember.name }} —
              <span class="text-n-slate-10 text-sm">{{
                selectedTierLabel
              }}</span>
            </h3>
          </div>
          <!-- role chips -->
          <div class="flex flex-wrap gap-2 mt-3">
            <button
              v-for="tier in TIERS"
              :key="tier.key"
              type="button"
              :disabled="tier.locked"
              class="px-3 py-1.5 rounded-full text-xs font-medium border"
              :class="
                tierOf(selectedMember) === tier.key
                  ? 'border-patra bg-patra/15 text-patra'
                  : 'border-n-weak text-n-slate-11 disabled:opacity-50'
              "
              @click="assignTier(selectedMember, tier)"
            >
              <span v-if="tier.locked">🔒 </span>{{ tier.label }}
            </button>
          </div>
        </div>

        <!-- permissions -->
        <div
          class="rounded-xl border border-n-weak bg-n-solid-1 p-4 flex flex-col gap-4"
        >
          <div class="flex items-center justify-between">
            <h3 class="text-sm font-semibold text-n-slate-12">Permissions</h3>
            <button
              type="button"
              :disabled="savingPerms"
              class="px-3 py-1.5 rounded-lg bg-patra text-white text-xs font-medium disabled:opacity-50"
              @click="savePermissions"
            >
              {{ savingPerms ? 'Saving…' : 'Save permissions' }}
            </button>
          </div>
          <div
            v-for="group in PERMISSION_GROUPS"
            :key="group.label"
            class="flex flex-col gap-2"
          >
            <div class="text-[11px] uppercase tracking-wide text-n-slate-10">
              {{ group.label }}
            </div>
            <div class="grid sm:grid-cols-2 gap-2">
              <label
                v-for="key in group.keys"
                :key="key"
                class="flex items-center justify-between gap-2 rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2"
              >
                <span class="text-sm text-n-slate-12 capitalize">{{
                  labelFor(key)
                }}</span>
                <input
                  type="checkbox"
                  :checked="hasPermission(key)"
                  class="accent-patra"
                  @change="togglePermission(key)"
                />
              </label>
            </div>
          </div>
        </div>

        <!-- name privacy -->
        <div
          class="rounded-xl border border-n-weak bg-n-solid-1 p-4 flex flex-col gap-3"
        >
          <h3 class="text-sm font-semibold text-n-slate-12">Name privacy</h3>
          <div class="flex gap-2 flex-wrap">
            <button
              v-for="state in PRIVACY_STATES"
              :key="state.key"
              type="button"
              class="px-3 py-1.5 rounded-lg border text-xs font-medium"
              :class="
                selectedPrivacy === state.key
                  ? 'border-patra bg-patra/15 text-patra'
                  : 'border-n-weak text-n-slate-11'
              "
              @click="setPrivacy(state.key)"
            >
              {{ state.label }}
            </button>
          </div>
          <p class="text-xs text-n-slate-11">
            Preview: a player named "Jordan Mitchell" shows as
            <span class="mono text-n-slate-12">{{ privacyPreview }}</span>
          </p>
        </div>

        <!-- granted main features (owner only) -->
        <div
          v-if="isOwnerViewer"
          class="rounded-xl border border-n-weak bg-n-solid-1 p-4 flex flex-col gap-3"
        >
          <h3 class="text-sm font-semibold text-n-slate-12">
            Granted main features
          </h3>
          <p class="text-xs text-n-slate-11">
            Owner-only powers you can delegate to a manager (no billing).
          </p>
          <div class="grid sm:grid-cols-2 gap-2">
            <label
              v-for="main in GRANTED_MAINS"
              :key="main.key"
              class="flex items-center justify-between gap-2 rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2"
            >
              <span class="text-sm text-n-slate-12">{{ main.label }}</span>
              <input
                type="checkbox"
                :checked="grants.includes(main.key)"
                :disabled="savingGrants"
                class="accent-patra"
                @change="toggleGrant(main.key)"
              />
            </label>
          </div>
        </div>

        <!-- channel / page access -->
        <div
          class="rounded-xl border border-n-weak bg-n-solid-1 p-4 flex flex-col gap-3"
        >
          <h3 class="text-sm font-semibold text-n-slate-12">
            Channel &amp; page access
          </h3>
          <p class="text-xs text-n-slate-11">
            Which inboxes this member can see.
          </p>
          <p v-if="!inboxes.length" class="text-xs text-n-slate-10">
            No inboxes yet.
          </p>
          <div v-else class="grid sm:grid-cols-2 gap-2">
            <label
              v-for="ibox in inboxes"
              :key="ibox.id"
              class="flex items-center justify-between gap-2 rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2"
            >
              <span class="text-sm text-n-slate-12 truncate">{{
                ibox.name
              }}</span>
              <input
                type="checkbox"
                :checked="memberInboxIds.includes(ibox.id)"
                class="accent-patra"
                @change="toggleInbox(ibox)"
              />
            </label>
          </div>
        </div>
      </section>
    </div>
  </div>
</template>

<style scoped>
.role-badge {
  font-size: 10px;
  font-weight: 600;
  padding: 2px 7px;
  border-radius: 9999px;
  white-space: nowrap;
  flex-shrink: 0;
}
.rb-owner {
  background: rgba(227, 160, 8, 0.16);
  color: #e3a008;
}
.rb-admin {
  background: rgba(110, 86, 207, 0.16);
  color: #8b5cf6;
}
.rb-manager {
  background: rgba(88, 166, 255, 0.16);
  color: #58a6ff;
}
.rb-cashier {
  background: rgba(63, 185, 80, 0.16);
  color: #3fb950;
}
.rb-agent {
  background: rgba(120, 120, 140, 0.16);
  color: var(--n-slate-11, #75727f);
}
.rb-viewer {
  border: 1px solid rgba(120, 120, 140, 0.4);
  color: var(--n-slate-10, #75727f);
}
</style>
