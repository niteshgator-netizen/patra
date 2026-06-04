<script setup>
import { ref, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import PatraBackupPagesAPI from 'dashboard/api/patraBackupPages';

const STATUSES = ['standby', 'warming', 'active', 'banned', 'retired'];
const PLATFORMS = ['facebook', 'instagram'];

const { showAlert } = useAlert();
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
  <div>
    <h2>Backup Pages</h2>

    <div v-if="loading">Loading...</div>

    <template v-else>
      <p v-if="pages.length === 0">No backup pages yet.</p>

      <table v-else border="1" cellpadding="6">
        <thead>
          <tr>
            <th>Platform</th>
            <th>Page ID</th>
            <th>Name</th>
            <th>Status</th>
            <th>Position</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="page in pages" :key="page.id">
            <td>{{ page.platform }}</td>
            <td>{{ page.page_id }}</td>
            <td>{{ page.page_name || '—' }}</td>
            <td>
              <select
                :value="page.status"
                :disabled="updatingStatus === page.id"
                @change="changeStatus(page, $event.target.value)"
              >
                <option v-for="s in STATUSES" :key="s" :value="s">
                  {{ s }}
                </option>
              </select>
            </td>
            <td>{{ page.position }}</td>
            <td>
              <button
                type="button"
                :disabled="removing === page.id"
                @click="removePage(page)"
              >
                {{ removing === page.id ? 'Removing...' : 'Remove' }}
              </button>
            </td>
          </tr>
        </tbody>
      </table>

      <h3>Add backup page</h3>
      <form @submit.prevent="addPage">
        <div>
          <label>Platform</label>
          <select v-model="newPage.platform">
            <option v-for="p in PLATFORMS" :key="p" :value="p">
              {{ p }}
            </option>
          </select>
        </div>
        <div>
          <label>Page ID</label>
          <input v-model="newPage.page_id" type="text" required />
        </div>
        <div>
          <label>Page name (optional)</label>
          <input v-model="newPage.page_name" type="text" />
        </div>
        <div>
          <label>Access token (optional)</label>
          <input v-model="newPage.access_token" type="password" autocomplete="off" />
        </div>
        <button type="submit" :disabled="saving">
          {{ saving ? 'Adding...' : 'Add page' }}
        </button>
      </form>
    </template>
  </div>
</template>
