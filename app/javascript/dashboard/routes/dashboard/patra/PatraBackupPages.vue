<script setup>
import { ref, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import PatraBackupPagesAPI from 'dashboard/api/patraBackupPages';

const STATUSES = ['standby', 'warming', 'active', 'banned', 'retired'];
const PLATFORMS = ['facebook', 'instagram'];

const showAlert = useAlert;
const pages = ref([]);
const loading = ref(true);
const saving = ref(false);
const removing = ref(null);
const updatingStatus = ref(null);

const newPage = ref({
  platform: 'facebook',
  page_id: '',
  page_name: '',
  access_token: '',
});

onMounted(async () => {
  await loadPages();
});

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
    });
    showAlert('Backup page added');
    newPage.value.page_id = '';
    newPage.value.page_name = '';
    newPage.value.access_token = '';
    await loadPages();
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
  } catch {
    showAlert('Failed to update status');
    await loadPages();
  } finally {
    updatingStatus.value = null;
  }
}

async function removePage(page) {
  const label = page.page_name || page.page_id;
  if (!confirm(`Remove backup page "${label}"?`)) return;
  removing.value = page.id;
  try {
    await PatraBackupPagesAPI.destroy(page.id);
    showAlert('Backup page removed');
    await loadPages();
  } catch {
    showAlert('Failed to remove backup page');
  } finally {
    removing.value = null;
  }
}
</script>

<template>
  <div class="flex flex-col gap-6 p-6">
    <header>
      <h2 class="text-2xl font-semibold text-n-slate-12">Backup Pages</h2>
      <p class="text-sm text-n-slate-11">
        Standby Facebook / Instagram pages to fail over to if one gets banned.
      </p>
    </header>

    <div v-if="loading" class="text-sm text-n-slate-11">Loading…</div>

    <template v-else>
      <p
        v-if="pages.length === 0"
        class="rounded-xl border border-n-weak bg-n-solid-1 py-12 text-center text-sm text-n-slate-11"
      >
        No backup pages yet.
      </p>

      <section v-else class="rounded-xl border border-n-weak bg-n-solid-1 p-4">
        <table class="w-full text-sm">
          <thead>
            <tr class="text-left text-n-slate-11">
              <th class="pb-2 font-medium">Platform</th>
              <th class="pb-2 font-medium">Page ID</th>
              <th class="pb-2 font-medium">Name</th>
              <th class="pb-2 font-medium">Status</th>
              <th class="pb-2 font-medium">Position</th>
              <th class="pb-2" />
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="page in pages"
              :key="page.id"
              class="border-t border-n-weak text-n-slate-12"
            >
              <td class="py-2 capitalize">{{ page.platform }}</td>
              <td class="py-2">{{ page.page_id }}</td>
              <td class="py-2">{{ page.page_name || '—' }}</td>
              <td class="py-2">
                <select
                  :value="page.status"
                  :disabled="updatingStatus === page.id"
                  class="p-1.5 rounded-lg bg-n-alpha-2 border border-n-weak text-xs text-n-slate-12 capitalize"
                  @change="changeStatus(page, $event.target.value)"
                >
                  <option v-for="s in STATUSES" :key="s" :value="s">
                    {{ s }}
                  </option>
                </select>
              </td>
              <td class="py-2 text-n-slate-11">{{ page.position }}</td>
              <td class="py-2 text-right">
                <button
                  type="button"
                  :disabled="removing === page.id"
                  class="px-3 py-1 rounded-lg border border-n-weak text-n-ruby-11 text-xs font-medium disabled:opacity-50"
                  @click="removePage(page)"
                >
                  {{ removing === page.id ? 'Removing…' : 'Remove' }}
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </section>

      <section
        class="max-w-xl rounded-xl border border-n-weak bg-n-solid-1 p-4 flex flex-col gap-3"
      >
        <h3 class="text-sm font-semibold text-n-slate-12">Add backup page</h3>
        <form class="flex flex-col gap-3" @submit.prevent="addPage">
          <label class="block">
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
            class="self-start px-4 py-2 rounded-lg bg-n-brand text-white text-sm font-medium disabled:opacity-50"
          >
            {{ saving ? 'Adding…' : 'Add page' }}
          </button>
        </form>
      </section>
    </template>
  </div>
</template>
