<script setup>
import { ref, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import PatraFacebookIdentitiesAPI from 'dashboard/api/patraFacebookIdentities';

const showAlert = useAlert;
const identities = ref([]);
const loading = ref(true);
const disconnecting = ref(null);

onMounted(async () => {
  await loadIdentities();
});

async function loadIdentities() {
  loading.value = true;
  try {
    const res = await PatraFacebookIdentitiesAPI.list();
    identities.value = res.data || [];
  } catch {
    showAlert('Failed to load connected Facebook accounts');
  } finally {
    loading.value = false;
  }
}

async function disconnect(identity) {
  if (!confirm(`Disconnect ${identity.fb_user_name}? This will unlink ${identity.inboxes.length} inbox(es).`)) return;
  disconnecting.value = identity.id;
  try {
    await PatraFacebookIdentitiesAPI.disconnect(identity.id);
    showAlert('Facebook account disconnected');
    await loadIdentities();
  } catch {
    showAlert('Failed to disconnect');
  } finally {
    disconnecting.value = null;
  }
}
</script>

<template>
  <div class="p-6 max-w-3xl">
    <h2 class="text-xl font-semibold text-n-slate-12 mb-6">Connected Facebook Accounts</h2>

    <div v-if="loading" class="text-n-slate-11">Loading...</div>

    <div v-else-if="identities.length === 0" class="text-n-slate-11">
      No Facebook accounts connected yet.
      <a href="/app/accounts/2/patra/connect-facebook" class="text-n-brand ml-2 underline">Connect one →</a>
    </div>

    <div v-else class="space-y-4">
      <div
        v-for="identity in identities"
        :key="identity.id"
        class="bg-n-solid-2 border border-n-weak rounded-xl p-4 flex items-start justify-between gap-4"
      >
        <div class="flex items-center gap-3">
          <img
            v-if="identity.fb_user_avatar_url"
            :src="identity.fb_user_avatar_url"
            class="w-10 h-10 rounded-full"
            @error="identity.fb_user_avatar_url = ''"
          />
          <div v-else class="w-10 h-10 rounded-full bg-n-brand flex items-center justify-center text-white font-bold">
            {{ identity.fb_user_name?.[0] }}
          </div>
          <div>
            <div class="text-n-slate-12 font-medium">{{ identity.fb_user_name }}</div>
            <div class="text-n-slate-11 text-sm mt-0.5">
              {{ identity.inboxes.length }} page(s) connected:
              <span v-for="(inbox, i) in identity.inboxes" :key="inbox.id">
                {{ inbox.name }}<span v-if="i < identity.inboxes.length - 1">, </span>
              </span>
            </div>
            <div class="text-xs mt-1" :class="identity.status === 'active' ? 'text-n-teal-10' : 'text-n-ruby-11'">
              {{ identity.status }}
            </div>
          </div>
        </div>
        <button
          class="text-sm px-3 py-1.5 rounded-lg border border-n-ruby-9 text-n-ruby-11 hover:bg-n-ruby-9 hover:text-white transition-colors"
          :disabled="disconnecting === identity.id"
          @click="disconnect(identity)"
        >
          {{ disconnecting === identity.id ? 'Disconnecting...' : 'Disconnect' }}
        </button>
      </div>
    </div>
  </div>
</template>
