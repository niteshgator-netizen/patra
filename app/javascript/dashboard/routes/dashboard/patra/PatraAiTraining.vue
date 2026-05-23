<script setup>
import { ref, computed, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import PatraAiTrainingAPI from 'dashboard/api/patraAiTraining';
import NextButton from 'dashboard/components-next/button/Button.vue';

// Phase H.10 item 10: unified AI Training page with three tabs —
// Upload Training Data, Review Queue, Secret Phrases.

const TABS = [
  { key: 'upload', label: 'Upload Training Data' },
  { key: 'review', label: 'Review Queue' },
  { key: 'phrases', label: 'Secret Phrases' },
];

const activeTab = ref('upload');

// ── Upload tab ─────────────────────────────────────────────────────

const uploads = ref([]);
const uploadsLoading = ref(false);
const selectedFile = ref(null);
const uploading = ref(false);
const dragOver = ref(false);

const fetchUploads = async () => {
  uploadsLoading.value = true;
  try {
    const { data } = await PatraAiTrainingAPI.listUploads();
    uploads.value = Array.isArray(data) ? data : [];
  } catch (e) {
    useAlert('Failed to load upload history.');
  } finally {
    uploadsLoading.value = false;
  }
};

const onFileChange = event => {
  const file = event.target.files?.[0];
  if (file) selectedFile.value = file;
};

const onDrop = event => {
  dragOver.value = false;
  const file = event.dataTransfer?.files?.[0];
  if (file) selectedFile.value = file;
};

const uploadFile = async () => {
  if (!selectedFile.value) {
    useAlert('Choose a .json file first.');
    return;
  }
  uploading.value = true;
  try {
    await PatraAiTrainingAPI.uploadTrainingFile(selectedFile.value);
    useAlert('Upload queued for processing.');
    selectedFile.value = null;
    await fetchUploads();
  } catch (e) {
    useAlert('Upload failed. Check the file format and try again.');
  } finally {
    uploading.value = false;
  }
};

const formatDate = iso => {
  if (!iso) return '—';
  return new Date(iso).toLocaleString();
};

const statusBadgeClass = status => {
  const map = {
    pending: 'bg-amber-100 text-amber-800',
    processing: 'bg-blue-100 text-blue-800',
    completed: 'bg-emerald-100 text-emerald-800',
    failed: 'bg-red-100 text-red-800',
    queued: 'bg-amber-100 text-amber-800',
    approved: 'bg-emerald-100 text-emerald-800',
    rejected: 'bg-red-100 text-red-800',
  };
  return map[status] || 'bg-n-slate-3 text-n-slate-11';
};

// ── Review queue tab ─────────────────────────────────────────────────

const candidates = ref([]);
const candidatesLoading = ref(false);
const reviewingId = ref(null);

const fetchCandidates = async () => {
  candidatesLoading.value = true;
  try {
    const { data } = await PatraAiTrainingAPI.listCandidates('queued');
    candidates.value = Array.isArray(data) ? data : [];
  } catch (e) {
    useAlert('Failed to load review queue.');
  } finally {
    candidatesLoading.value = false;
  }
};

const reviewCandidate = async (id, status) => {
  reviewingId.value = id;
  try {
    await PatraAiTrainingAPI.updateCandidate(id, status);
    candidates.value = candidates.value.filter(c => c.id !== id);
    useAlert(status === 'approved' ? 'Example approved and added to training.' : 'Example rejected.');
  } catch (e) {
    useAlert('Could not update that item. Try again.');
  } finally {
    reviewingId.value = null;
  }
};

const formatScore = score => `${Math.round(Number(score || 0) * 100)}%`;

// ── Secret phrases tab ─────────────────────────────────────────────

const phrases = ref([]);
const phrasesLoading = ref(false);
const phraseForm = ref({
  phrase: '',
  action: 'notify_only',
  active: true,
});
const editingId = ref(null);
const editForm = ref({ phrase: '', action: 'notify_only', active: true });
const savingPhrase = ref(false);

const fetchPhrases = async () => {
  phrasesLoading.value = true;
  try {
    const { data } = await PatraAiTrainingAPI.listSecretPhrases();
    phrases.value = Array.isArray(data) ? data : [];
  } catch (e) {
    useAlert('Failed to load secret phrases.');
  } finally {
    phrasesLoading.value = false;
  }
};

const maskPhrase = phrase => {
  const text = (phrase || '').toString();
  if (text.length <= 2) return '***';
  return `${text[0]}${'*'.repeat(Math.min(text.length - 2, 8))}${text[text.length - 1]}`;
};

const createPhrase = async () => {
  if (!phraseForm.value.phrase.trim()) {
    useAlert('Enter a phrase.');
    return;
  }
  savingPhrase.value = true;
  try {
    await PatraAiTrainingAPI.createSecretPhrase({ ...phraseForm.value });
    phraseForm.value = { phrase: '', action: 'notify_only', active: true };
    await fetchPhrases();
    useAlert('Secret phrase added.');
  } catch (e) {
    useAlert('Could not add phrase. It may already exist.');
  } finally {
    savingPhrase.value = false;
  }
};

const startEdit = phrase => {
  editingId.value = phrase.id;
  editForm.value = {
    phrase: phrase.phrase,
    action: phrase.action,
    active: phrase.active,
  };
};

const cancelEdit = () => {
  editingId.value = null;
};

const saveEdit = async id => {
  savingPhrase.value = true;
  try {
    await PatraAiTrainingAPI.updateSecretPhrase(id, { ...editForm.value });
    editingId.value = null;
    await fetchPhrases();
    useAlert('Secret phrase updated.');
  } catch (e) {
    useAlert('Could not update phrase.');
  } finally {
    savingPhrase.value = false;
  }
};

const togglePhraseActive = async phrase => {
  try {
    await PatraAiTrainingAPI.updateSecretPhrase(phrase.id, {
      phrase: phrase.phrase,
      action: phrase.action,
      active: !phrase.active,
    });
    await fetchPhrases();
  } catch (e) {
    useAlert('Could not toggle phrase.');
  }
};

const deletePhrase = async id => {
  if (!window.confirm('Delete this secret phrase?')) return;
  try {
    await PatraAiTrainingAPI.deleteSecretPhrase(id);
    await fetchPhrases();
    useAlert('Secret phrase deleted.');
  } catch (e) {
    useAlert('Could not delete phrase.');
  }
};

// ── Tab switching ──────────────────────────────────────────────────

const switchTab = key => {
  activeTab.value = key;
  if (key === 'upload') fetchUploads();
  if (key === 'review') fetchCandidates();
  if (key === 'phrases') fetchPhrases();
};

const pageTitle = computed(() => 'AI Training');

onMounted(() => {
  fetchUploads();
});
</script>

<template>
  <div class="flex flex-col w-full max-w-4xl mx-auto p-6">
    <header class="mb-6">
      <p class="text-xs uppercase tracking-wide text-n-slate-10 mb-1">
        Settings / AI Training
      </p>
      <h1 class="text-2xl font-semibold text-n-slate-12">{{ pageTitle }}</h1>
      <p class="text-sm text-n-slate-11 mt-1">
        Upload training examples, review human takeovers, and manage secret phrases.
      </p>
    </header>

    <nav class="flex gap-1 border-b border-n-slate-6 mb-6">
      <button
        v-for="tab in TABS"
        :key="tab.key"
        type="button"
        class="px-4 py-2 text-sm font-medium border-b-2 -mb-px transition-colors"
        :class="
          activeTab === tab.key
            ? 'border-n-brand text-n-brand'
            : 'border-transparent text-n-slate-11 hover:text-n-slate-12'
        "
        @click="switchTab(tab.key)"
      >
        {{ tab.label }}
      </button>
    </nav>

    <!-- Tab 1: Upload -->
    <section v-if="activeTab === 'upload'" class="space-y-6">
      <div
        class="rounded-xl border-2 border-dashed p-8 text-center transition-colors"
        :class="
          dragOver
            ? 'border-n-brand bg-n-brand/5'
            : 'border-n-slate-6 bg-n-slate-2'
        "
        @dragover.prevent="dragOver = true"
        @dragleave.prevent="dragOver = false"
        @drop.prevent="onDrop"
      >
        <p class="text-sm text-n-slate-11 mb-3">
          Drop a <code class="text-xs bg-n-slate-3 px-1 rounded">.json</code> training file here, or browse.
        </p>
        <input
          type="file"
          accept=".json,application/json"
          class="block mx-auto text-sm mb-3"
          @change="onFileChange"
        />
        <p v-if="selectedFile" class="text-sm text-n-slate-12 mb-3">
          Selected: {{ selectedFile.name }}
        </p>
        <NextButton
          blue
          :is-loading="uploading"
          :disabled="!selectedFile"
          @click="uploadFile"
        >
          Upload
        </NextButton>
      </div>

      <div>
        <h2 class="text-lg font-medium text-n-slate-12 mb-3">Upload history</h2>
        <div v-if="uploadsLoading" class="text-sm text-n-slate-11">Loading…</div>
        <div
          v-else-if="uploads.length === 0"
          class="text-sm text-n-slate-11 rounded-lg border border-n-slate-6 p-4"
        >
          No uploads yet.
        </div>
        <div v-else class="overflow-x-auto rounded-lg border border-n-slate-6">
          <table class="w-full text-sm">
            <thead class="bg-n-slate-2 text-n-slate-11 text-left">
              <tr>
                <th class="px-4 py-2 font-medium">Filename</th>
                <th class="px-4 py-2 font-medium">Status</th>
                <th class="px-4 py-2 font-medium">Pairs</th>
                <th class="px-4 py-2 font-medium">Skipped</th>
                <th class="px-4 py-2 font-medium">Date</th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="upload in uploads"
                :key="upload.id"
                class="border-t border-n-slate-6"
              >
                <td class="px-4 py-2 text-n-slate-12">{{ upload.filename }}</td>
                <td class="px-4 py-2">
                  <span
                    class="inline-block px-2 py-0.5 rounded text-xs font-medium"
                    :class="statusBadgeClass(upload.status)"
                  >
                    {{ upload.status }}
                  </span>
                </td>
                <td class="px-4 py-2">{{ upload.pairs_created ?? '—' }}</td>
                <td class="px-4 py-2">{{ upload.pairs_skipped ?? '—' }}</td>
                <td class="px-4 py-2 text-n-slate-11">{{ formatDate(upload.created_at) }}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </section>

    <!-- Tab 2: Review queue -->
    <section v-if="activeTab === 'review'" class="space-y-4">
      <p class="text-sm text-n-slate-11">
        Human replies captured when agents take over from Bella. Approve to add them to training data.
      </p>
      <div v-if="candidatesLoading" class="text-sm text-n-slate-11">Loading…</div>
      <div
        v-else-if="candidates.length === 0"
        class="text-sm text-n-slate-11 rounded-lg border border-n-slate-6 p-6 text-center"
      >
        Review queue is empty — nothing waiting for approval.
      </div>
      <div v-else class="space-y-4">
        <article
          v-for="candidate in candidates"
          :key="candidate.id"
          class="rounded-lg border border-n-slate-6 p-4 space-y-3"
        >
          <div class="flex items-center justify-between gap-2">
            <span
              class="inline-block px-2 py-0.5 rounded text-xs font-medium"
              :class="statusBadgeClass(candidate.status)"
            >
              {{ formatScore(candidate.confidence_score) }} confidence
            </span>
            <span class="text-xs text-n-slate-10">{{ formatDate(candidate.created_at) }}</span>
          </div>
          <div>
            <p class="text-xs uppercase text-n-slate-10 mb-1">Customer</p>
            <p class="text-sm text-n-slate-12 whitespace-pre-wrap">{{ candidate.customer_text }}</p>
          </div>
          <div>
            <p class="text-xs uppercase text-n-slate-10 mb-1">Human reply</p>
            <p class="text-sm text-n-slate-12 whitespace-pre-wrap">{{ candidate.human_reply }}</p>
          </div>
          <div class="flex gap-2 pt-1">
            <NextButton
              blue
              size="sm"
              :is-loading="reviewingId === candidate.id"
              @click="reviewCandidate(candidate.id, 'approved')"
            >
              Approve
            </NextButton>
            <NextButton
              faded
              slate
              size="sm"
              :disabled="reviewingId === candidate.id"
              @click="reviewCandidate(candidate.id, 'rejected')"
            >
              Reject
            </NextButton>
          </div>
        </article>
      </div>
    </section>

    <!-- Tab 3: Secret phrases -->
    <section v-if="activeTab === 'phrases'" class="space-y-6">
      <div class="rounded-lg border border-n-slate-6 p-4 space-y-3 bg-n-slate-2">
        <h2 class="text-sm font-medium text-n-slate-12">Add secret phrase</h2>
        <div class="grid gap-3 sm:grid-cols-2">
          <label class="block">
            <span class="text-xs text-n-slate-11 mb-1 block">Phrase</span>
            <input
              v-model="phraseForm.phrase"
              type="text"
              maxlength="50"
              class="w-full text-sm rounded-lg border border-n-slate-6 px-3 py-2 bg-n-solid-1"
              placeholder="e.g. chargeback"
            />
          </label>
          <label class="block">
            <span class="text-xs text-n-slate-11 mb-1 block">Action</span>
            <select
              v-model="phraseForm.action"
              class="w-full text-sm rounded-lg border border-n-slate-6 px-3 py-2 bg-n-solid-1"
            >
              <option value="notify_only">Notify only</option>
              <option value="pause_ai_and_notify">Pause AI and notify</option>
            </select>
          </label>
        </div>
        <label class="flex items-center gap-2 text-sm text-n-slate-12">
          <input v-model="phraseForm.active" type="checkbox" />
          Active
        </label>
        <NextButton blue :is-loading="savingPhrase" @click="createPhrase">
          Add phrase
        </NextButton>
      </div>

      <div>
        <h2 class="text-lg font-medium text-n-slate-12 mb-3">Configured phrases</h2>
        <div v-if="phrasesLoading" class="text-sm text-n-slate-11">Loading…</div>
        <div
          v-else-if="phrases.length === 0"
          class="text-sm text-n-slate-11 rounded-lg border border-n-slate-6 p-4"
        >
          No secret phrases yet.
        </div>
        <div v-else class="overflow-x-auto rounded-lg border border-n-slate-6">
          <table class="w-full text-sm">
            <thead class="bg-n-slate-2 text-n-slate-11 text-left">
              <tr>
                <th class="px-4 py-2 font-medium">Phrase</th>
                <th class="px-4 py-2 font-medium">Action</th>
                <th class="px-4 py-2 font-medium">Active</th>
                <th class="px-4 py-2 font-medium">Triggers</th>
                <th class="px-4 py-2 font-medium">Actions</th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="phrase in phrases"
                :key="phrase.id"
                class="border-t border-n-slate-6"
              >
                <td class="px-4 py-2">
                  <template v-if="editingId === phrase.id">
                    <input
                      v-model="editForm.phrase"
                      type="text"
                      maxlength="50"
                      class="w-full text-sm rounded border border-n-slate-6 px-2 py-1"
                    />
                  </template>
                  <template v-else>
                    <span class="font-mono text-n-slate-12">{{ maskPhrase(phrase.phrase) }}</span>
                  </template>
                </td>
                <td class="px-4 py-2">
                  <template v-if="editingId === phrase.id">
                    <select
                      v-model="editForm.action"
                      class="text-sm rounded border border-n-slate-6 px-2 py-1"
                    >
                      <option value="notify_only">Notify only</option>
                      <option value="pause_ai_and_notify">Pause AI and notify</option>
                    </select>
                  </template>
                  <template v-else>
                    {{ phrase.action === 'pause_ai_and_notify' ? 'Pause AI + notify' : 'Notify only' }}
                  </template>
                </td>
                <td class="px-4 py-2">
                  <button
                    type="button"
                    class="text-xs px-2 py-0.5 rounded font-medium"
                    :class="
                      phrase.active
                        ? 'bg-emerald-100 text-emerald-800'
                        : 'bg-n-slate-3 text-n-slate-11'
                    "
                    @click="togglePhraseActive(phrase)"
                  >
                    {{ phrase.active ? 'On' : 'Off' }}
                  </button>
                </td>
                <td class="px-4 py-2 text-n-slate-11">{{ phrase.trigger_count ?? 0 }}</td>
                <td class="px-4 py-2">
                  <div class="flex gap-2">
                    <template v-if="editingId === phrase.id">
                      <button
                        type="button"
                        class="text-xs text-n-brand hover:underline"
                        @click="saveEdit(phrase.id)"
                      >
                        Save
                      </button>
                      <button
                        type="button"
                        class="text-xs text-n-slate-11 hover:underline"
                        @click="cancelEdit"
                      >
                        Cancel
                      </button>
                    </template>
                    <template v-else>
                      <button
                        type="button"
                        class="text-xs text-n-brand hover:underline"
                        @click="startEdit(phrase)"
                      >
                        Edit
                      </button>
                      <button
                        type="button"
                        class="text-xs text-red-600 hover:underline"
                        @click="deletePhrase(phrase.id)"
                      >
                        Delete
                      </button>
                    </template>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </section>
  </div>
</template>
