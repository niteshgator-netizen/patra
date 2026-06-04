<script setup>
import { ref, onMounted, onUnmounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import PatraCashierClaimsAPI from 'dashboard/api/patraCashierClaims';

const { showAlert } = useAlert();
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
  <div>
    <h2>Cashier Queue</h2>

    <div v-if="loading">Loading...</div>

    <template v-else>
      <p v-if="claims.length === 0">No pending claims.</p>

      <table v-else border="1" cellpadding="6">
        <thead>
          <tr>
            <th>Action</th>
            <th>Amount</th>
            <th>Game</th>
            <th>Contact</th>
            <th>Expires</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="claim in claims" :key="claim.id">
            <td>{{ claim.action_type }}</td>
            <td>{{ claim.amount }}</td>
            <td>{{ claim.game_slug || '—' }}</td>
            <td>{{ contactName(claim) }}</td>
            <td>{{ claim.expires_at || '—' }}</td>
            <td>
              <button
                v-if="claim.status === 'pending'"
                type="button"
                :disabled="acting === claim.id"
                @click="claimItem(claim.id)"
              >
                {{ acting === claim.id ? 'Claiming...' : 'Claim' }}
              </button>
              <button
                v-if="claim.status === 'claimed'"
                type="button"
                :disabled="acting === claim.id"
                @click="completeItem(claim.id)"
              >
                {{ acting === claim.id ? 'Completing...' : 'Complete' }}
              </button>
            </td>
          </tr>
        </tbody>
      </table>
    </template>
  </div>
</template>
