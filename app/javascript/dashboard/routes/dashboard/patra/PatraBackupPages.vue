<script setup>
import { ref, computed, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import PatraBackupPagesAPI from 'dashboard/api/patraBackupPages';

// Coverage model (B-PAGES): every customer is connected to ALL live pages BEFORE any ban, so if one
// page goes down the others already reach them. No failover, no migration — just coverage.
const STATUSES = ['standby', 'warming', 'active', 'banned', 'retired'];
const PLATFORMS = ['facebook', 'instagram'];
const ROLES = ['main', 'backup'];
const CADENCES = [
  { value: 2, label: 'Every 2 days' },
  { value: 3, label: 'Every 3 days' },
  { value: 7, label: 'Weekly' },
];

const showAlert = useAlert;
const pages = ref([]);
const loading = ref(true);
const saving = ref(false);
const removing = ref(null);
const updatingStatus = ref(null);

// Coverage + drip state
const coverage = ref(null);
const loadingCoverage = ref(true);
const drip = ref({
  backup_invite_message: '',
  backup_drip_enabled: false,
  backup_drip_cadence_days: 3,
  drip_master_enabled: false,
});
const inviteDraft = ref('');
const savingInvite = ref(false);
const savingDrip = ref(false);

const newPage = ref({
  platform: 'facebook',
  page_id: '',
  page_name: '',
  access_token: '',
  role: 'backup',
});

// per-page connection counts keyed by page id (live pages only, from /coverage)
const perPage = computed(() => {
  const map = {};
  (coverage.value?.per_page || []).forEach(p => {
    map[p.id] = p.connections || 0;
  });
  return map;
});
const maxConnections = computed(() =>
  Math.max(1, ...Object.values(perPage.value))
);
const fullyPct = computed(() =>
  Math.round(coverage.value?.fully_connected_pct || 0)
);
const breakdown = computed(() => coverage.value?.breakdown || {});
// SVG ring geometry (circumference of r=52)
const RING_CIRC = 2 * Math.PI * 52;
const ringOffset = computed(() => RING_CIRC * (1 - fullyPct.value / 100));

function isLive(page) {
  return !['banned', 'retired'].includes(page.status);
}

function protectionPct(page) {
  const total = coverage.value?.total_customers || 0;
  if (!total) return 0;
  return Math.round(((perPage.value[page.id] || 0) / total) * 100);
}

function protectionTone(pct) {
  if (pct >= 80) return 'good';
  if (pct >= 50) return 'warn';
  return 'bad';
}

const fullyPctLabel = computed(() => `${fullyPct.value}%`);

function roleBadgeClass(page) {
  return page.role === 'main'
    ? 'bg-patra/15 text-patra'
    : 'bg-n-alpha-2 text-n-slate-11';
}

function statusPillClass(page) {
  return isLive(page)
    ? 'bg-n-teal-3 text-n-teal-11'
    : 'bg-n-ruby-3 text-n-ruby-11';
}

async function loadPages() {
  loading.value = true;
  try {
    const res = await PatraBackupPagesAPI.list();
    pages.value = res.data || [];
  } catch {
    showAlert('Failed to load backup pages');
  } finally {
    loading.value = false;
  }
}

async function loadCoverage() {
  loadingCoverage.value = true;
  try {
    const res = await PatraBackupPagesAPI.coverage();
    coverage.value = res.data || {};
    if (res.data?.drip) {
      drip.value = { ...drip.value, ...res.data.drip };
      inviteDraft.value = res.data.drip.backup_invite_message || '';
    }
  } catch {
    showAlert('Failed to load coverage');
  } finally {
    loadingCoverage.value = false;
  }
}

async function addPage() {
  if (!newPage.value.page_id.trim()) {
    showAlert('Page ID is required');
    return;
  }
  saving.value = true;
  try {
    await PatraBackupPagesAPI.create({
      platform: newPage.value.platform,
      page_id: newPage.value.page_id.trim(),
      page_name: newPage.value.page_name.trim() || undefined,
      access_token: newPage.value.access_token.trim() || undefined,
      role: newPage.value.role,
    });
    showAlert('Backup page added');
    newPage.value.page_id = '';
    newPage.value.page_name = '';
    newPage.value.access_token = '';
    await Promise.all([loadPages(), loadCoverage()]);
  } catch {
    showAlert('Failed to add backup page');
  } finally {
    saving.value = false;
  }
}

async function changeStatus(page, status) {
  if (page.status === status) return;
  updatingStatus.value = page.id;
  try {
    await PatraBackupPagesAPI.update(page.id, { status });
    page.status = status;
    showAlert('Status updated');
    await loadCoverage();
  } catch {
    showAlert('Failed to update status');
    await loadPages();
  } finally {
    updatingStatus.value = null;
  }
}

async function changeRole(page, role) {
  if (page.role === role) return;
  try {
    await PatraBackupPagesAPI.update(page.id, { role });
    page.role = role;
    showAlert('Role updated');
    await loadCoverage();
  } catch {
    showAlert('Failed to update role');
    await loadPages();
  }
}

async function removePage(page) {
  const label = page.page_name || page.page_id;
  // eslint-disable-next-line no-alert
  if (!window.confirm(`Remove backup page "${label}"?`)) return;
  removing.value = page.id;
  try {
    await PatraBackupPagesAPI.destroy(page.id);
    showAlert('Backup page removed');
    await Promise.all([loadPages(), loadCoverage()]);
  } catch {
    showAlert('Failed to remove backup page');
  } finally {
    removing.value = null;
  }
}

async function saveInvite() {
  savingInvite.value = true;
  try {
    const res = await PatraBackupPagesAPI.dripConfig({
      backup_invite_message: inviteDraft.value,
    });
    drip.value = { ...drip.value, ...res.data };
    showAlert('Connect-up invite saved');
  } catch {
    showAlert('Failed to save invite');
  } finally {
    savingInvite.value = false;
  }
}

async function saveDrip(patch) {
  savingDrip.value = true;
  try {
    const res = await PatraBackupPagesAPI.dripConfig(patch);
    drip.value = { ...drip.value, ...res.data };
    showAlert('Follow-up settings saved');
  } catch {
    showAlert('Failed to save follow-up settings');
  } finally {
    savingDrip.value = false;
  }
}

function toggleDrip() {
  saveDrip({ backup_drip_enabled: !drip.value.backup_drip_enabled });
}

function setCadence(value) {
  if (drip.value.backup_drip_cadence_days === value) return;
  saveDrip({ backup_drip_cadence_days: value });
}

onMounted(async () => {
  await Promise.all([loadPages(), loadCoverage()]);
});
</script>

<template>
  <div class="flex flex-col gap-6 p-6">
    <header>
      <h2 class="text-2xl font-semibold text-n-slate-12">Backup Pages</h2>
      <p class="text-sm text-n-slate-11">
        Keep every customer connected to all your pages — so if one goes down,
        the others already reach them.
      </p>
    </header>

    <!-- COVERAGE SUMMARY -->
    <section
      class="rounded-xl border border-n-weak bg-n-solid-1 p-5 flex flex-col gap-5 md:flex-row md:items-center md:gap-8"
    >
      <template v-if="loadingCoverage">
        <span class="text-sm text-n-slate-11">Loading coverage…</span>
      </template>
      <template v-else>
        <!-- ring -->
        <div class="relative shrink-0 self-center w-[132px] h-[132px]">
          <svg width="132" height="132" viewBox="0 0 132 132">
            <circle
              cx="66"
              cy="66"
              r="52"
              fill="none"
              stroke="currentColor"
              class="text-n-slate-4"
              stroke-width="12"
            />
            <circle
              cx="66"
              cy="66"
              r="52"
              fill="none"
              stroke="currentColor"
              class="text-patra"
              stroke-width="12"
              stroke-linecap="round"
              :stroke-dasharray="RING_CIRC"
              :stroke-dashoffset="ringOffset"
              transform="rotate(-90 66 66)"
            />
          </svg>
          <div
            class="absolute inset-0 flex flex-col items-center justify-center"
          >
            <span class="text-2xl font-semibold text-n-slate-12 mono">
              {{ fullyPctLabel }}
            </span>
            <span class="text-[11px] text-n-slate-11">fully protected</span>
          </div>
        </div>

        <div class="flex flex-col gap-3 grow">
          <p class="text-sm text-n-slate-12">
            <span class="font-semibold mono">{{
              coverage?.fully_connected || 0
            }}</span>
            of
            <span class="font-semibold mono">{{
              coverage?.total_customers || 0
            }}</span>
            customers connected to every live page
          </p>
          <!-- breakdown -->
          <div class="grid grid-cols-2 sm:grid-cols-4 gap-2">
            <div class="rounded-lg border border-n-weak bg-n-alpha-1 p-3">
              <div class="text-lg font-semibold text-n-slate-12 mono">
                {{ breakdown.all || 0 }}
              </div>
              <div class="text-[11px] text-n-slate-11">All live pages</div>
            </div>
            <div class="rounded-lg border border-n-weak bg-n-alpha-1 p-3">
              <div class="text-lg font-semibold text-n-slate-12 mono">
                {{ breakdown.three_backups || 0 }}
              </div>
              <div class="text-[11px] text-n-slate-11">3 backups</div>
            </div>
            <div class="rounded-lg border border-n-weak bg-n-alpha-1 p-3">
              <div class="text-lg font-semibold text-n-slate-12 mono">
                {{ breakdown.two_backups || 0 }}
              </div>
              <div class="text-[11px] text-n-slate-11">2 backups</div>
            </div>
            <div class="rounded-lg border border-n-weak bg-n-alpha-1 p-3">
              <div class="text-lg font-semibold text-n-slate-12 mono">
                {{ breakdown.main_only || 0 }}
              </div>
              <div class="text-[11px] text-n-slate-11">Main only</div>
            </div>
          </div>
        </div>
      </template>
    </section>

    <div v-if="loading" class="text-sm text-n-slate-11">Loading…</div>

    <template v-else>
      <!-- LIVE PAGES -->
      <section
        class="rounded-xl border border-n-weak bg-n-solid-1 p-4 flex flex-col gap-3"
      >
        <div class="flex items-center justify-between">
          <h3 class="text-sm font-semibold text-n-slate-12">Live pages</h3>
          <span class="text-[11px] text-n-slate-11">1 main + 4 backups</span>
        </div>

        <p
          v-if="pages.length === 0"
          class="rounded-lg border border-n-weak bg-n-alpha-1 py-10 text-center text-sm text-n-slate-11"
        >
          No pages yet — add your main page and a few backups below.
        </p>

        <ul v-else class="flex flex-col gap-2">
          <li
            v-for="page in pages"
            :key="page.id"
            class="rounded-lg border border-n-weak bg-n-alpha-1 p-3 flex flex-col gap-2 sm:flex-row sm:items-center sm:gap-4"
          >
            <div class="flex items-center gap-2 min-w-0 sm:w-56">
              <span
                class="text-[10px] font-semibold px-1.5 py-0.5 rounded uppercase tracking-wide"
                :class="roleBadgeClass(page)"
              >
                {{ page.role === 'main' ? 'Main' : 'Backup' }}
              </span>
              <span class="truncate text-sm text-n-slate-12">{{
                page.page_name || page.page_id
              }}</span>
            </div>

            <!-- per-page connection count + bar -->
            <div class="grow min-w-0">
              <div
                class="flex items-center justify-between text-[11px] text-n-slate-11"
              >
                <span class="mono">{{ perPage[page.id] || 0 }} connected</span>
                <span class="mono">{{ protectionPct(page) }}%</span>
              </div>
              <div class="mt-1 h-1.5 rounded-full bg-n-slate-4 overflow-hidden">
                <div
                  class="h-full rounded-full"
                  :class="{
                    'bg-n-teal-9':
                      protectionTone(protectionPct(page)) === 'good',
                    'bg-n-amber-9':
                      protectionTone(protectionPct(page)) === 'warn',
                    'bg-n-ruby-9':
                      protectionTone(protectionPct(page)) === 'bad',
                  }"
                  :style="{
                    width: `${Math.min(100, ((perPage[page.id] || 0) / maxConnections) * 100)}%`,
                  }"
                />
              </div>
            </div>

            <!-- status pill (live/banned) -->
            <span
              class="text-[11px] px-2 py-0.5 rounded-full font-medium"
              :class="statusPillClass(page)"
            >
              {{ isLive(page) ? 'Live' : 'Banned' }}
            </span>

            <!-- controls -->
            <div class="flex items-center gap-2">
              <select
                :value="page.role || 'backup'"
                class="p-1 rounded-lg bg-n-alpha-2 border border-n-weak text-xs text-n-slate-12 capitalize"
                @change="changeRole(page, $event.target.value)"
              >
                <option v-for="r in ROLES" :key="r" :value="r">{{ r }}</option>
              </select>
              <select
                :value="page.status"
                :disabled="updatingStatus === page.id"
                class="p-1 rounded-lg bg-n-alpha-2 border border-n-weak text-xs text-n-slate-12 capitalize"
                @change="changeStatus(page, $event.target.value)"
              >
                <option v-for="s in STATUSES" :key="s" :value="s">
                  {{ s }}
                </option>
              </select>
              <button
                type="button"
                :disabled="removing === page.id"
                class="px-2.5 py-1 rounded-lg border border-n-weak text-n-ruby-11 text-xs font-medium disabled:opacity-50"
                @click="removePage(page)"
              >
                {{ removing === page.id ? '…' : 'Remove' }}
              </button>
            </div>
          </li>
        </ul>
      </section>

      <!-- CONNECT-UP INVITE -->
      <section
        class="max-w-2xl rounded-xl border border-n-weak bg-n-solid-1 p-4 flex flex-col gap-3"
      >
        <h3 class="text-sm font-semibold text-n-slate-12">Connect-up invite</h3>
        <p class="text-xs text-n-slate-11">
          The message sent asking customers to follow your other pages so you
          never lose touch.
        </p>
        <textarea
          v-model="inviteDraft"
          rows="3"
          placeholder="Follow our other pages so we never lose touch — send a quick hi to each: %{links}"
          class="w-full p-2 rounded-lg bg-n-alpha-2 border border-n-weak text-sm text-n-slate-12"
        />
        <p class="text-[11px] text-n-slate-10">
          Tip: include <code class="mono">%{links}</code> where the m.me links
          should appear.
        </p>
        <button
          type="button"
          :disabled="savingInvite"
          class="self-start px-4 py-2 rounded-lg bg-patra text-white text-sm font-medium disabled:opacity-50"
          @click="saveInvite"
        >
          {{ savingInvite ? 'Saving…' : 'Save invite' }}
        </button>
      </section>

      <!-- AUTO FOLLOW-UP -->
      <section
        class="max-w-2xl rounded-xl border border-n-weak bg-n-solid-1 p-4 flex flex-col gap-3"
      >
        <div class="flex items-center justify-between">
          <h3 class="text-sm font-semibold text-n-slate-12">Auto follow-up</h3>
          <button
            type="button"
            role="switch"
            :aria-checked="drip.backup_drip_enabled"
            :disabled="savingDrip"
            class="relative w-11 h-6 rounded-full transition-colors disabled:opacity-50"
            :class="drip.backup_drip_enabled ? 'bg-patra' : 'bg-n-slate-5'"
            @click="toggleDrip"
          >
            <span
              class="absolute top-0.5 left-0.5 w-5 h-5 rounded-full bg-white transition-transform"
              :class="{ 'translate-x-5': drip.backup_drip_enabled }"
            />
          </button>
        </div>
        <p class="text-xs text-n-slate-11">
          Re-invite customers who aren't connected to every live page yet, on a
          set cadence.
        </p>

        <div class="flex gap-2">
          <button
            v-for="c in CADENCES"
            :key="c.value"
            type="button"
            :disabled="savingDrip"
            class="px-3 py-1.5 rounded-lg border text-xs font-medium"
            :class="
              drip.backup_drip_cadence_days === c.value
                ? 'border-patra bg-patra/15 text-patra'
                : 'border-n-weak text-n-slate-11'
            "
            @click="setCadence(c.value)"
          >
            {{ c.label }}
          </button>
        </div>

        <p class="text-[11px] text-n-slate-10">
          Next round every {{ drip.backup_drip_cadence_days }} days → reaches
          {{ coverage?.incomplete_count || 0 }} incomplete customers.
        </p>

        <!-- master kill switch banner -->
        <p
          v-if="!drip.drip_master_enabled"
          class="rounded-lg border border-n-amber-6 bg-n-amber-3 text-n-amber-11 text-xs px-3 py-2"
        >
          Sending is OFF until ops enable the master switch. Your settings are
          saved and take effect once it's on.
        </p>
        <p
          v-else-if="drip.backup_drip_enabled"
          class="rounded-lg border border-n-teal-6 bg-n-teal-3 text-n-teal-11 text-xs px-3 py-2"
        >
          Follow-up sending is live.
        </p>
      </section>

      <!-- ADD PAGE -->
      <section
        class="max-w-xl rounded-xl border border-n-weak bg-n-solid-1 p-4 flex flex-col gap-3"
      >
        <h3 class="text-sm font-semibold text-n-slate-12">Add page</h3>
        <form class="flex flex-col gap-3" @submit.prevent="addPage">
          <div class="flex gap-3">
            <label class="block grow">
              <span class="text-xs text-n-slate-11">Role</span>
              <select
                v-model="newPage.role"
                class="w-full mt-1 p-2 rounded-lg bg-n-alpha-2 border border-n-weak text-sm text-n-slate-12 capitalize"
              >
                <option v-for="r in ROLES" :key="r" :value="r">{{ r }}</option>
              </select>
            </label>
            <label class="block grow">
              <span class="text-xs text-n-slate-11">Platform</span>
              <select
                v-model="newPage.platform"
                class="w-full mt-1 p-2 rounded-lg bg-n-alpha-2 border border-n-weak text-sm text-n-slate-12 capitalize"
              >
                <option v-for="p in PLATFORMS" :key="p" :value="p">
                  {{ p }}
                </option>
              </select>
            </label>
          </div>
          <label class="block">
            <span class="text-xs text-n-slate-11">Page ID</span>
            <input
              v-model="newPage.page_id"
              type="text"
              required
              class="w-full mt-1 p-2 rounded-lg bg-n-alpha-2 border border-n-weak text-sm text-n-slate-12"
            />
          </label>
          <label class="block">
            <span class="text-xs text-n-slate-11">Page name (optional)</span>
            <input
              v-model="newPage.page_name"
              type="text"
              class="w-full mt-1 p-2 rounded-lg bg-n-alpha-2 border border-n-weak text-sm text-n-slate-12"
            />
          </label>
          <label class="block">
            <span class="text-xs text-n-slate-11">Access token (optional)</span>
            <input
              v-model="newPage.access_token"
              type="password"
              autocomplete="off"
              class="w-full mt-1 p-2 rounded-lg bg-n-alpha-2 border border-n-weak text-sm text-n-slate-12"
            />
          </label>
          <button
            type="submit"
            :disabled="saving"
            class="self-start px-4 py-2 rounded-lg bg-patra text-white text-sm font-medium disabled:opacity-50"
          >
            {{ saving ? 'Adding…' : 'Add page' }}
          </button>
        </form>
      </section>
    </template>
  </div>
</template>
