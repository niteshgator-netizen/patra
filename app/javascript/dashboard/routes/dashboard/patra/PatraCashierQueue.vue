<script setup>
import { ref, onMounted, onUnmounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import PatraCashierClaimsAPI from 'dashboard/api/patraCashierClaims';

const showAlert = useAlert;
const claims = ref([]);
const loading = ref(true);
const acting = ref(null);
let pollInterval = null;

function contactName(claim) {
  if (claim.contact?.name) return claim.contact.name;
  if (claim.contact_name) return claim.contact_name;
  return '—';
}

async function loadClaims() {
  try {
    const res = await PatraCashierClaimsAPI.list();
    claims.value = res.data || [];
  } catch {
    showAlert('Failed to load cashier queue');
  } finally {
    loading.value = false;
  }
}

async function claimItem(id) {
  acting.value = id;
  try {
    await PatraCashierClaimsAPI.claim(id);
    await loadClaims();
  } catch {
    showAlert('Failed to claim');
  } finally {
    acting.value = null;
  }
}

async function completeItem(id) {
  acting.value = id;
  try {
    await PatraCashierClaimsAPI.complete(id);
    await loadClaims();
  } catch {
    showAlert('Failed to complete');
  } finally {
    acting.value = null;
  }
}

onMounted(async () => {
  await loadClaims();
  pollInterval = setInterval(loadClaims, 15_000);
});

onUnmounted(() => clearInterval(pollInterval));
</script>

<template>
  <div class="flex flex-col gap-4 p-6">
    <header>
      <h2 class="text-2xl font-semibold text-n-slate-12">Cashier Queue</h2>
      <p class="text-sm text-n-slate-11">
        Pending load, cashout and freeplay claims.
      </p>
    </header>

    <div v-if="loading" class="text-sm text-n-slate-11">Loading…</div>

    <template v-else>
      <p
        v-if="claims.length === 0"
        class="rounded-xl border border-n-weak bg-n-solid-1 py-12 text-center text-sm text-n-slate-11"
      >
        No pending claims.
      </p>

      <section
        v-else
        class="rounded-xl border border-n-weak bg-n-solid-1 p-4 overflow-x-auto"
      >
        <table class="w-full min-w-[560px] text-sm">
          <thead>
            <tr class="text-left text-n-slate-11">
              <th class="pb-2 font-medium">Action</th>
              <th class="pb-2 font-medium">Amount</th>
              <th class="pb-2 font-medium">Game</th>
              <th class="pb-2 font-medium">Contact</th>
              <th class="pb-2 font-medium">Expires</th>
              <th class="pb-2" />
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="claim in claims"
              :key="claim.id"
              class="border-t border-n-weak text-n-slate-12"
            >
              <td class="py-2">{{ claim.action_type }}</td>
              <td class="py-2">{{ claim.amount }}</td>
              <td class="py-2">{{ claim.game_slug || '—' }}</td>
              <td class="py-2">{{ contactName(claim) }}</td>
              <td class="py-2 text-n-slate-11">{{ claim.expires_at || '—' }}</td>
              <td class="py-2 text-right">
                <button
                  v-if="claim.status === 'pending'"
                  type="button"
                  :disabled="acting === claim.id"
                  class="px-3 py-1 rounded-lg bg-n-brand text-white text-xs font-medium disabled:opacity-50"
                  @click="claimItem(claim.id)"
                >
                  {{ acting === claim.id ? 'Claiming…' : 'Claim' }}
                </button>
                <button
                  v-if="claim.status === 'claimed'"
                  type="button"
                  :disabled="acting === claim.id"
                  class="px-3 py-1 rounded-lg border border-n-weak text-n-slate-12 text-xs font-medium disabled:opacity-50"
                  @click="completeItem(claim.id)"
                >
                  {{ acting === claim.id ? 'Completing…' : 'Complete' }}
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </section>
    </template>
  </div>
</template>
