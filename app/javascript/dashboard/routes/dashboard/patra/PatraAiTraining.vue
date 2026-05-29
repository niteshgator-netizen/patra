<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import PatraAiTrainingAPI from 'dashboard/api/patraAiTraining';

// Phase H.10 item 10: unified AI Training page with three tabs —
// Upload Training Data, Review Queue, Secret Phrases.

const TABS = [
  { key: 'upload', label: 'Upload Training Data' },
  { key: 'review', label: 'Review Queue' },
  { key: 'phrases', label: 'Secret Phrases' },
];

const activeTab = ref('upload');
const rootRef = ref(null);
const spotlightRef = ref(null);
const fileInputRef = ref(null);

const emptyPlaceholder = '—';
const breadcrumb = 'Settings / AI Training';
const pageTitle = 'Patra AI Training';
const pageSubtitle =
  'Upload training examples, review human takeovers, and manage secret phrases.';
const statTrainingPairsLabel = 'Training pairs in knowledge base';
const statEmbeddingsValue = '512-dim';
const statEmbeddingsLabel = 'Voyage embeddings';
const statHandleRateLabel = 'AI handle rate this week';
const statAwaitingReviewLabel = 'Awaiting review';
const uploadCardTitle = 'Upload training data';
const dropzonePrefix = 'Drop a ';
const dropzoneJsonExt = '.json';
const dropzoneMiddle = ' training file here, or ';
const dropzoneBrowseLabel = 'browse';
const dropzoneHint = 'customer_text + cashier_text pairs · max 10MB';
const selectedFilePrefix = 'Selected:';
const chooseFileLabel = 'Choose file';
const uploadLabel = 'Upload';
const uploadingLabel = 'Uploading…';
const uploadHistoryTitle = 'Upload history';
const loadingLabel = 'Loading…';
const noUploadsLabel = 'No uploads yet.';
const reviewQueueTitle = 'Review queue';
const reviewQueueDesc =
  'Human replies captured when agents take over from Patra AI. Approve to add them to the training data.';
const reviewQueueEmpty =
  'Review queue is empty — nothing waiting for approval.';
const confidenceSuffix = ' confidence';
const viewConversationLabel = 'View conversation';
const customerLabel = 'Customer';
const humanReplyLabel = 'Human reply';
const savingLabel = 'Saving…';
const approveTrainingLabel = '✓ Approve into training';
const discardLabel = 'Discard';
const addSecretPhraseTitle = 'Add secret phrase';
const addSecretPhraseDesc =
  'When a customer message contains a secret phrase, Patra AI can notify you or pause itself so a human takes over.';
const phraseFieldLabel = 'Phrase';
const phrasePlaceholder = 'e.g. let me talk to a real person';
const actionLabel = 'Action';
const notifyOnlyLabel = 'Notify only';
const pauseAiNotifyLabel = 'Pause AI & notify';
const activeLabel = 'Active';
const addingPhraseLabel = 'Adding…';
const addPhraseLabel = 'Add phrase';
const configuredPhrasesTitle = 'Configured phrases';
const noPhrasesLabel = 'No secret phrases yet.';
const triggersSuffix = ' triggers';
const togglePhraseAriaLabel = 'Toggle phrase active';
const editLabel = 'Edit';
const deletePhraseAriaLabel = 'Delete phrase';
const deletePhraseIcon = '🗑';
const saveLabel = 'Save';
const cancelLabel = 'Cancel';
const deletePhraseConfirm = 'Delete this secret phrase?';
const ingestedLabel = '✓ ingested';

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

const openFilePicker = () => {
  fileInputRef.value?.click();
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
    if (fileInputRef.value) fileInputRef.value.value = '';
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
    pending: 'pat-at-uh-tag--pending',
    processing: 'pat-at-uh-tag--processing',
    completed: 'pat-at-uh-tag--completed',
    failed: 'pat-at-uh-tag--failed',
    queued: 'pat-at-uh-tag--pending',
    approved: 'pat-at-uh-tag--completed',
    rejected: 'pat-at-uh-tag--failed',
  };
  return map[status] || 'pat-at-uh-tag--default';
};

const uploadStatusLabel = status => {
  if (status === 'completed') return ingestedLabel;
  return status;
};

const uploadMetaLine = upload => {
  const pairs = upload.pairs_created ?? '—';
  const skipped = upload.pairs_skipped ?? 0;
  const skippedPart = skipped ? ` · ${skipped} skipped` : '';
  return `${pairs} pairs${skippedPart} · ${formatDate(upload.created_at)}`;
};

// ── Review queue tab ─────────────────────────────────────────────────

const candidates = ref([]);
const candidatesLoading = ref(false);
const candidatesLoaded = ref(false);
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
    candidatesLoaded.value = true;
  }
};

const reviewCandidate = async (id, status) => {
  reviewingId.value = id;
  try {
    await PatraAiTrainingAPI.updateCandidate(id, status);
    candidates.value = candidates.value.filter(c => c.id !== id);
    useAlert(
      status === 'approved'
        ? 'Example approved and added to training.'
        : 'Example rejected.'
    );
  } catch (e) {
    useAlert('Could not update that item. Try again.');
  } finally {
    reviewingId.value = null;
  }
};

const formatScore = score => `${Math.round(Number(score || 0) * 100)}%`;

const candidateConfidenceLabel = score =>
  `${formatScore(score)}${confidenceSuffix}`;

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

const phraseActionLabel = action =>
  action === 'pause_ai_and_notify' ? pauseAiNotifyLabel : notifyOnlyLabel;

const setPhraseFormAction = action => {
  phraseForm.value.action = action;
};

const setEditFormAction = action => {
  editForm.value.action = action;
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
  // eslint-disable-next-line no-alert
  if (!window.confirm(deletePhraseConfirm)) return;
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

const trainingPairsTotal = computed(() => {
  if (uploadsLoading.value) return null;
  const total = uploads.value
    .filter(u => u.status === 'completed')
    .reduce((sum, u) => sum + (Number(u.pairs_created) || 0), 0);
  return total > 0 ? total.toLocaleString() : null;
});

const awaitingReviewCount = computed(() => {
  if (!candidatesLoaded.value || candidatesLoading.value) return null;
  return candidates.value.length;
});

function noopPlaceholder() {}

function onMouseMove(event) {
  const spot = spotlightRef.value;
  if (spot) {
    spot.style.left = `${event.clientX}px`;
    spot.style.top = `${event.clientY}px`;
    spot.style.opacity = '1';
  }

  const card = event.target.closest?.('.pat-at-card');
  if (card) {
    const rect = card.getBoundingClientRect();
    card.style.setProperty('--gx', `${event.clientX - rect.left}px`);
    card.style.setProperty('--gy', `${event.clientY - rect.top}px`);
  }

  const rag = event.target.closest?.('.pat-at-rag');
  if (rag) {
    const rect = rag.getBoundingClientRect();
    rag.style.setProperty('--mx', `${event.clientX - rect.left}px`);
    rag.style.setProperty('--my', `${event.clientY - rect.top}px`);
  }
}

function onMouseLeave() {
  if (spotlightRef.value) spotlightRef.value.style.opacity = '0';
}

onMounted(() => {
  fetchUploads();
  fetchCandidates();
  rootRef.value?.addEventListener('mousemove', onMouseMove);
  document.addEventListener('mouseleave', onMouseLeave);
});

onUnmounted(() => {
  rootRef.value?.removeEventListener('mousemove', onMouseMove);
  document.removeEventListener('mouseleave', onMouseLeave);
});
</script>

<template>
  <div ref="rootRef" class="pat-at-root">
    <div ref="spotlightRef" class="pat-at-spotlight" aria-hidden="true" />
    <div class="pat-at-mesh" aria-hidden="true" />

    <div class="pat-at-main">
      <div class="pat-at-topbar">
        <div class="pat-at-bc">{{ breadcrumb }}</div>
        <h1 class="pat-at-title">{{ pageTitle }}</h1>
        <div class="pat-at-sub">
          {{ pageSubtitle }}
        </div>
      </div>

      <div class="pat-at-content">
        <div class="pat-at-rag-stats">
          <!-- TODO: wire backend — full knowledge-base pair count -->
          <button type="button" class="pat-at-rag" @click="noopPlaceholder">
            <div
              class="pat-at-rag-n"
              :class="{ 'pat-at-rag-n--accent': trainingPairsTotal }"
            >
              {{ trainingPairsTotal ?? emptyPlaceholder }}
            </div>
            <div class="pat-at-rag-l">{{ statTrainingPairsLabel }}</div>
          </button>
          <!-- TODO: wire backend — live embedding stats -->
          <button type="button" class="pat-at-rag" @click="noopPlaceholder">
            <div class="pat-at-rag-n">{{ statEmbeddingsValue }}</div>
            <div class="pat-at-rag-l">{{ statEmbeddingsLabel }}</div>
          </button>
          <!-- TODO: wire backend — AI handle rate -->
          <button type="button" class="pat-at-rag" @click="noopPlaceholder">
            <div class="pat-at-rag-n">{{ emptyPlaceholder }}</div>
            <div class="pat-at-rag-l">{{ statHandleRateLabel }}</div>
          </button>
          <button type="button" class="pat-at-rag" @click="noopPlaceholder">
            <div
              class="pat-at-rag-n"
              :class="{ 'pat-at-rag-n--accent': awaitingReviewCount !== null }"
            >
              {{ awaitingReviewCount ?? emptyPlaceholder }}
            </div>
            <div class="pat-at-rag-l">{{ statAwaitingReviewLabel }}</div>
          </button>
        </div>

        <div class="pat-at-tabs">
          <button
            v-for="tab in TABS"
            :key="tab.key"
            type="button"
            class="pat-at-tab"
            :class="{ 'pat-at-tab--active': activeTab === tab.key }"
            @click="switchTab(tab.key)"
          >
            <svg
              v-if="tab.key === 'upload'"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="2"
              aria-hidden="true"
            >
              <path
                d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4M17 8l-5-5-5 5M12 3v12"
              />
            </svg>
            <svg
              v-else-if="tab.key === 'review'"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="2"
              aria-hidden="true"
            >
              <path
                d="M9 11l3 3L22 4M21 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11"
              />
            </svg>
            <svg
              v-else
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="2"
              aria-hidden="true"
            >
              <rect x="3" y="11" width="18" height="11" rx="2" />
              <path d="M7 11V7a5 5 0 0 1 10 0v4" />
            </svg>
            {{ tab.label }}
            <span
              v-if="tab.key === 'review' && awaitingReviewCount"
              class="pat-at-tab-badge"
            >
              {{ awaitingReviewCount }}
            </span>
          </button>
        </div>

        <!-- Upload tab -->
        <section v-show="activeTab === 'upload'" class="pat-at-pane">
          <div class="pat-at-card">
            <div class="pat-at-card-t">
              <span class="pat-at-card-dot" />
              {{ uploadCardTitle }}
            </div>
            <div
              class="pat-at-dropzone"
              :class="{ 'pat-at-dropzone--over': dragOver }"
              @dragover.prevent="dragOver = true"
              @dragleave.prevent="dragOver = false"
              @drop.prevent="onDrop"
              @click="openFilePicker"
            >
              <div class="pat-at-dz-ic">
                <svg
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="2"
                  aria-hidden="true"
                >
                  <path
                    d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4M17 8l-5-5-5 5M12 3v12"
                  />
                </svg>
              </div>
              <div class="pat-at-dz-t">
                {{ dropzonePrefix }}
                <span class="pat-at-dz-em">{{ dropzoneJsonExt }}</span>
                {{ dropzoneMiddle }}
                <span class="pat-at-dz-em">{{ dropzoneBrowseLabel }}</span>
              </div>
              <div class="pat-at-dz-s">
                {{ dropzoneHint }}
              </div>
              <p v-if="selectedFile" class="pat-at-dz-selected">
                {{ selectedFilePrefix }} {{ selectedFile.name }}
              </p>
              <input
                ref="fileInputRef"
                type="file"
                accept=".json,application/json"
                class="pat-at-file-input"
                @change="onFileChange"
                @click.stop
              />
              <div class="pat-at-dz-actions" @click.stop>
                <button
                  type="button"
                  class="pat-at-btn"
                  @click="openFilePicker"
                >
                  {{ chooseFileLabel }}
                </button>
                <button
                  type="button"
                  class="pat-at-btn pat-at-btn--primary"
                  :disabled="!selectedFile || uploading"
                  @click="uploadFile"
                >
                  {{ uploading ? uploadingLabel : uploadLabel }}
                </button>
              </div>
            </div>
          </div>

          <div class="pat-at-card">
            <div class="pat-at-card-t">
              <span class="pat-at-card-dot" />
              {{ uploadHistoryTitle }}
            </div>
            <div v-if="uploadsLoading" class="pat-at-empty">
              {{ loadingLabel }}
            </div>
            <div v-else-if="uploads.length === 0" class="pat-at-empty">
              {{ noUploadsLabel }}
            </div>
            <template v-else>
              <div
                v-for="upload in uploads"
                :key="upload.id"
                class="pat-at-uh-row"
              >
                <div class="pat-at-uh-ic">
                  <svg
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="2"
                    aria-hidden="true"
                  >
                    <path
                      d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"
                    />
                    <path d="M14 2v6h6" />
                  </svg>
                </div>
                <div class="pat-at-uh-info">
                  <div class="pat-at-uh-un">{{ upload.filename }}</div>
                  <div class="pat-at-uh-um">{{ uploadMetaLine(upload) }}</div>
                </div>
                <span
                  class="pat-at-uh-tag"
                  :class="statusBadgeClass(upload.status)"
                >
                  {{ uploadStatusLabel(upload.status) }}
                </span>
              </div>
            </template>
          </div>
        </section>

        <!-- Review queue tab -->
        <section v-show="activeTab === 'review'" class="pat-at-pane">
          <div class="pat-at-card">
            <div class="pat-at-card-t">
              <span class="pat-at-card-dot" />
              {{ reviewQueueTitle }}
            </div>
            <p class="pat-at-pane-desc">
              {{ reviewQueueDesc }}
            </p>
            <div v-if="candidatesLoading" class="pat-at-empty">
              {{ loadingLabel }}
            </div>
            <div v-else-if="candidates.length === 0" class="pat-at-empty">
              {{ reviewQueueEmpty }}
            </div>
            <template v-else>
              <article
                v-for="candidate in candidates"
                :key="candidate.id"
                class="pat-at-rq"
              >
                <div class="pat-at-rq-top">
                  <span class="pat-at-rq-meta">
                    {{ candidateConfidenceLabel(candidate.confidence_score) }}
                  </span>
                  <!-- TODO: wire backend — game / player / agent metadata -->
                  <button
                    type="button"
                    class="pat-at-rq-stub"
                    @click="noopPlaceholder"
                  >
                    {{ viewConversationLabel }}
                  </button>
                  <span class="pat-at-rq-time">{{
                    formatDate(candidate.created_at)
                  }}</span>
                </div>
                <div class="pat-at-rq-msg pat-at-rq-msg--cust">
                  <span class="pat-at-rq-ml">{{ customerLabel }}</span>
                  {{ candidate.customer_text }}
                </div>
                <div class="pat-at-rq-msg pat-at-rq-msg--agent">
                  <span class="pat-at-rq-ml">{{ humanReplyLabel }}</span>
                  {{ candidate.human_reply }}
                </div>
                <div class="pat-at-rq-actions">
                  <button
                    type="button"
                    class="pat-at-rq-btn pat-at-rq-btn--approve"
                    :disabled="reviewingId === candidate.id"
                    @click="reviewCandidate(candidate.id, 'approved')"
                  >
                    {{
                      reviewingId === candidate.id
                        ? savingLabel
                        : approveTrainingLabel
                    }}
                  </button>
                  <button
                    type="button"
                    class="pat-at-rq-btn pat-at-rq-btn--discard"
                    :disabled="reviewingId === candidate.id"
                    @click="reviewCandidate(candidate.id, 'rejected')"
                  >
                    {{ discardLabel }}
                  </button>
                </div>
              </article>
            </template>
          </div>
        </section>

        <!-- Secret phrases tab -->
        <section v-show="activeTab === 'phrases'" class="pat-at-pane">
          <div class="pat-at-card">
            <div class="pat-at-card-t">
              <span class="pat-at-card-dot" />
              {{ addSecretPhraseTitle }}
            </div>
            <p class="pat-at-pane-desc">
              {{ addSecretPhraseDesc }}
            </p>
            <div class="pat-at-sp-form">
              <div class="pat-at-sp-field">
                <label for="pat-at-phrase-input">{{ phraseFieldLabel }}</label>
                <input
                  id="pat-at-phrase-input"
                  v-model="phraseForm.phrase"
                  type="text"
                  maxlength="50"
                  :placeholder="phrasePlaceholder"
                />
              </div>
              <div class="pat-at-sp-actions-row">
                <div>
                  <span class="pat-at-sp-action-label">{{ actionLabel }}</span>
                  <div class="pat-at-sp-radio">
                    <button
                      type="button"
                      class="pat-at-sp-opt"
                      :class="{
                        'pat-at-sp-opt--sel':
                          phraseForm.action === 'notify_only',
                      }"
                      @click="setPhraseFormAction('notify_only')"
                    >
                      <span class="pat-at-sp-rd" />
                      {{ notifyOnlyLabel }}
                    </button>
                    <button
                      type="button"
                      class="pat-at-sp-opt pat-at-sp-opt--danger"
                      :class="{
                        'pat-at-sp-opt--sel':
                          phraseForm.action === 'pause_ai_and_notify',
                      }"
                      @click="setPhraseFormAction('pause_ai_and_notify')"
                    >
                      <span class="pat-at-sp-rd" />
                      {{ pauseAiNotifyLabel }}
                    </button>
                  </div>
                </div>
                <label class="pat-at-sp-active">
                  <input v-model="phraseForm.active" type="checkbox" />
                  {{ activeLabel }}
                </label>
                <button
                  type="button"
                  class="pat-at-btn pat-at-btn--primary pat-at-sp-add"
                  :disabled="savingPhrase"
                  @click="createPhrase"
                >
                  {{ savingPhrase ? addingPhraseLabel : addPhraseLabel }}
                </button>
              </div>
            </div>
          </div>

          <div class="pat-at-card">
            <div class="pat-at-card-t">
              <span class="pat-at-card-dot" />
              {{ configuredPhrasesTitle }}
            </div>
            <div v-if="phrasesLoading" class="pat-at-empty">
              {{ loadingLabel }}
            </div>
            <div v-else-if="phrases.length === 0" class="pat-at-empty">
              {{ noPhrasesLabel }}
            </div>
            <template v-else>
              <div
                v-for="phrase in phrases"
                :key="phrase.id"
                class="pat-at-sp-row"
              >
                <template v-if="editingId === phrase.id">
                  <div class="pat-at-sp-edit">
                    <input
                      v-model="editForm.phrase"
                      type="text"
                      maxlength="50"
                      class="pat-at-sp-edit-input"
                    />
                    <div class="pat-at-sp-radio pat-at-sp-radio--compact">
                      <button
                        type="button"
                        class="pat-at-sp-opt"
                        :class="{
                          'pat-at-sp-opt--sel':
                            editForm.action === 'notify_only',
                        }"
                        @click="setEditFormAction('notify_only')"
                      >
                        <span class="pat-at-sp-rd" />
                        {{ notifyOnlyLabel }}
                      </button>
                      <button
                        type="button"
                        class="pat-at-sp-opt pat-at-sp-opt--danger"
                        :class="{
                          'pat-at-sp-opt--sel':
                            editForm.action === 'pause_ai_and_notify',
                        }"
                        @click="setEditFormAction('pause_ai_and_notify')"
                      >
                        <span class="pat-at-sp-rd" />
                        {{ pauseAiNotifyLabel }}
                      </button>
                    </div>
                    <label class="pat-at-sp-active pat-at-sp-active--inline">
                      <input v-model="editForm.active" type="checkbox" />
                      {{ activeLabel }}
                    </label>
                    <div class="pat-at-sp-edit-actions">
                      <button
                        type="button"
                        class="pat-at-btn pat-at-btn--primary pat-at-btn--sm"
                        :disabled="savingPhrase"
                        @click="saveEdit(phrase.id)"
                      >
                        {{ saveLabel }}
                      </button>
                      <button
                        type="button"
                        class="pat-at-btn pat-at-btn--sm"
                        @click="cancelEdit"
                      >
                        {{ cancelLabel }}
                      </button>
                    </div>
                  </div>
                </template>
                <template v-else>
                  <span class="pat-at-sp-phrase">{{
                    maskPhrase(phrase.phrase)
                  }}</span>
                  <span
                    class="pat-at-sp-act"
                    :class="
                      phrase.action === 'pause_ai_and_notify'
                        ? 'pat-at-sp-act--pause'
                        : 'pat-at-sp-act--notify'
                    "
                  >
                    {{ phraseActionLabel(phrase.action) }}
                  </span>
                  <span class="pat-at-sp-triggers mono">
                    {{ phrase.trigger_count ?? 0 }}{{ triggersSuffix }}
                  </span>
                  <button
                    type="button"
                    class="pat-at-sp-sw"
                    :class="{ 'pat-at-sp-sw--off': !phrase.active }"
                    :aria-pressed="phrase.active"
                    :aria-label="togglePhraseAriaLabel"
                    @click="togglePhraseActive(phrase)"
                  >
                    <i />
                  </button>
                  <button
                    type="button"
                    class="pat-at-sp-edit-link"
                    @click="startEdit(phrase)"
                  >
                    {{ editLabel }}
                  </button>
                  <button
                    type="button"
                    class="pat-at-sp-del"
                    :aria-label="deletePhraseAriaLabel"
                    @click="deletePhrase(phrase.id)"
                  >
                    {{ deletePhraseIcon }}
                  </button>
                </template>
              </div>
            </template>
          </div>
        </section>
      </div>
    </div>
  </div>
</template>

<style scoped>
.pat-at-root {
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
  --amber: #e3a008;
  --red: #f85149;
  --blue: #58a6ff;
  --inset: rgba(255, 255, 255, 0.045);
  --shadow: 0 24px 60px -20px rgba(0, 0, 0, 0.8);
  --mesh-1: rgba(110, 86, 207, 0.16);
  --mesh-2: rgba(139, 92, 246, 0.1);
  --mesh-3: rgba(236, 72, 153, 0.05);

  position: relative;
  width: 100%;
  height: 100%;
  min-height: 0;
  overflow-y: auto;
  overflow-x: hidden;
  background: var(--canvas);
  color: var(--text);
  font-family: Inter, ui-sans-serif, system-ui, sans-serif;
  font-size: 14px;
  -webkit-font-smoothing: antialiased;
}

.mono {
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  font-variant-numeric: tabular-nums;
}

.pat-at-spotlight {
  position: fixed;
  width: 460px;
  height: 460px;
  border-radius: 50%;
  background: radial-gradient(
    circle,
    rgba(110, 86, 207, 0.16),
    rgba(110, 86, 207, 0.04) 42%,
    transparent 66%
  );
  pointer-events: none;
  z-index: 0;
  transform: translate(-50%, -50%);
  opacity: 0;
  transition: opacity 0.5s;
  mix-blend-mode: screen;
  filter: blur(12px);
}

.pat-at-mesh {
  position: fixed;
  inset: 0;
  pointer-events: none;
  z-index: 0;
  overflow: hidden;
}

.pat-at-mesh::before,
.pat-at-mesh::after {
  content: '';
  position: absolute;
  border-radius: 50%;
  filter: blur(100px);
}

.pat-at-mesh::before {
  top: -15%;
  right: -5%;
  width: 700px;
  height: 560px;
  background:
    radial-gradient(circle at 40% 40%, var(--mesh-1), transparent 60%),
    radial-gradient(circle at 70% 70%, var(--mesh-2), transparent 60%);
  animation: pat-at-mesh-a 22s ease-in-out infinite alternate;
}

.pat-at-mesh::after {
  bottom: -20%;
  left: 10%;
  width: 560px;
  height: 500px;
  background: radial-gradient(
    circle at 50% 50%,
    var(--mesh-3),
    transparent 65%
  );
  animation: pat-at-mesh-b 28s ease-in-out infinite alternate;
}

.pat-at-main {
  position: relative;
  z-index: 1;
}

.pat-at-topbar {
  padding: 22px 30px 0;
}

.pat-at-bc {
  font-size: 11px;
  color: var(--text-4);
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  margin-bottom: 6px;
}

.pat-at-title {
  font-family: 'Space Grotesk', ui-sans-serif, system-ui, sans-serif;
  font-weight: 600;
  font-size: 26px;
  letter-spacing: -0.02em;
  margin: 0;
}

.pat-at-sub {
  font-size: 13px;
  color: var(--text-3);
  margin-top: 3px;
}

.pat-at-content {
  padding: 22px 30px 60px;
  max-width: 1000px;
}

.pat-at-rag-stats {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 14px;
  margin-bottom: 22px;
}

.pat-at-rag {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 14px;
  padding: 16px 18px;
  position: relative;
  overflow: hidden;
  transition: all 0.3s cubic-bezier(0.34, 1.56, 0.64, 1);
  cursor: pointer;
  text-align: left;
  animation: pat-at-m-in 0.5s cubic-bezier(0.23, 1, 0.32, 1) backwards;
}

.pat-at-rag::after {
  content: '';
  position: absolute;
  inset: 0;
  background: radial-gradient(
    160px circle at var(--mx, 50%) var(--my, 50%),
    rgba(110, 86, 207, 0.16),
    transparent
  );
  opacity: 0;
  transition: opacity 0.3s;
}

.pat-at-rag:hover {
  border-color: var(--patra);
  transform: translateY(-4px);
  box-shadow:
    0 16px 32px -10px rgba(0, 0, 0, 0.5),
    0 0 22px rgba(110, 86, 207, 0.2);
}

.pat-at-rag:hover::after {
  opacity: 1;
}

.pat-at-rag-n {
  font-family: 'Space Grotesk', ui-sans-serif, system-ui, sans-serif;
  font-weight: 700;
  font-size: 26px;
  position: relative;
}

.pat-at-rag-n--accent {
  background: linear-gradient(135deg, var(--patra-2), var(--patra-3));
  -webkit-background-clip: text;
  background-clip: text;
  -webkit-text-fill-color: transparent;
}

.pat-at-rag-l {
  font-size: 11px;
  color: var(--text-3);
  margin-top: 4px;
  position: relative;
}

.pat-at-tabs {
  display: flex;
  gap: 5px;
  border-bottom: 1px solid var(--border);
  margin-bottom: 22px;
}

.pat-at-tab {
  font-size: 14px;
  font-weight: 500;
  padding: 11px 18px;
  color: var(--text-3);
  cursor: pointer;
  position: relative;
  border-radius: 10px 10px 0 0;
  transition: all 0.2s;
  display: flex;
  align-items: center;
  gap: 7px;
  background: transparent;
  border: none;
}

.pat-at-tab svg {
  width: 15px;
  height: 15px;
}

.pat-at-tab:hover {
  color: var(--text);
  background: var(--surface-2);
}

.pat-at-tab--active {
  color: var(--text);
}

.pat-at-tab--active::after {
  content: '';
  position: absolute;
  bottom: -1px;
  left: 14px;
  right: 14px;
  height: 2px;
  background: linear-gradient(90deg, var(--patra), var(--patra-2));
  border-radius: 2px;
  box-shadow: 0 0 8px var(--patra-glow);
}

.pat-at-tab-badge {
  font-size: 10px;
  font-weight: 600;
  background: var(--patra);
  color: #fff;
  border-radius: 20px;
  padding: 1px 7px;
  font-family: 'JetBrains Mono', ui-monospace, monospace;
}

.pat-at-pane {
  animation: pat-at-fade-in 0.3s;
}

.pat-at-card {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 16px;
  padding: 22px;
  margin-bottom: 16px;
  position: relative;
  isolation: isolate;
  transition:
    transform 0.35s cubic-bezier(0.34, 1.56, 0.64, 1),
    box-shadow 0.35s,
    border-color 0.25s;
  animation: pat-at-m-in 0.5s cubic-bezier(0.23, 1, 0.32, 1) backwards;
}

.pat-at-card::before {
  content: '';
  position: absolute;
  inset: 0;
  border-radius: inherit;
  pointer-events: none;
  opacity: 0;
  transition: opacity 0.3s;
  background: radial-gradient(
    260px circle at var(--gx, 50%) var(--gy, 50%),
    rgba(110, 86, 207, 0.15),
    transparent 70%
  );
  z-index: -1;
}

.pat-at-card:hover::before {
  opacity: 1;
}

.pat-at-card:hover {
  transform: translateY(-4px) scale(1.008);
  box-shadow:
    0 18px 40px -14px rgba(0, 0, 0, 0.55),
    0 0 26px rgba(110, 86, 207, 0.18);
  border-color: var(--patra);
}

.pat-at-card-t {
  font-family: 'Space Grotesk', ui-sans-serif, system-ui, sans-serif;
  font-weight: 600;
  font-size: 15px;
  display: flex;
  align-items: center;
  gap: 8px;
  margin-bottom: 16px;
}

.pat-at-card-dot {
  width: 7px;
  height: 7px;
  border-radius: 50%;
  background: var(--patra-2);
  box-shadow: 0 0 8px var(--patra-glow);
  flex-shrink: 0;
}

.pat-at-pane-desc {
  font-size: 13px;
  color: var(--text-3);
  margin: -8px 0 16px;
  line-height: 1.5;
}

.pat-at-empty {
  font-size: 13px;
  color: var(--text-3);
  padding: 16px;
  text-align: center;
  border: 1px dashed var(--border-hi);
  border-radius: 12px;
  background: var(--canvas);
}

.pat-at-dropzone {
  border: 2px dashed var(--border-hi);
  border-radius: 14px;
  padding: 44px 20px;
  text-align: center;
  transition: all 0.3s;
  cursor: pointer;
  background: var(--canvas);
}

.pat-at-dropzone:hover,
.pat-at-dropzone--over {
  border-color: var(--patra);
  background: rgba(110, 86, 207, 0.05);
}

.pat-at-dz-ic {
  width: 54px;
  height: 54px;
  border-radius: 14px;
  background: linear-gradient(
    135deg,
    rgba(110, 86, 207, 0.16),
    rgba(139, 92, 246, 0.06)
  );
  display: flex;
  align-items: center;
  justify-content: center;
  margin: 0 auto 14px;
  border: 1px solid rgba(139, 92, 246, 0.3);
}

.pat-at-dz-ic svg {
  width: 26px;
  height: 26px;
  color: var(--patra-3);
}

.pat-at-dz-t {
  font-size: 15px;
  font-weight: 500;
}

.pat-at-dz-t b,
.pat-at-dz-em {
  color: var(--patra-3);
  font-weight: 500;
}

.pat-at-dz-s {
  font-size: 12px;
  color: var(--text-3);
  margin-top: 6px;
  font-family: 'JetBrains Mono', ui-monospace, monospace;
}

.pat-at-dz-selected {
  font-size: 13px;
  color: var(--text-2);
  margin-top: 12px;
}

.pat-at-file-input {
  position: absolute;
  width: 0;
  height: 0;
  opacity: 0;
  pointer-events: none;
}

.pat-at-dz-actions {
  display: flex;
  gap: 10px;
  justify-content: center;
  margin-top: 18px;
}

.pat-at-btn {
  font-size: 13px;
  font-weight: 600;
  padding: 10px 18px;
  border-radius: 10px;
  border: 1px solid var(--border-hi);
  background: var(--surface-2);
  color: var(--text);
  cursor: pointer;
  transition: all 0.22s cubic-bezier(0.34, 1.56, 0.64, 1);
}

.pat-at-btn:hover:not(:disabled) {
  transform: translateY(-2px) scale(1.02);
  box-shadow: 0 6px 16px rgba(0, 0, 0, 0.3);
  border-color: var(--patra);
}

.pat-at-btn:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

.pat-at-btn--primary {
  background: linear-gradient(135deg, var(--patra), var(--patra-deep));
  border-color: transparent;
  color: #fff;
  box-shadow: 0 4px 14px var(--patra-glow);
}

.pat-at-btn--primary:hover:not(:disabled) {
  filter: brightness(1.12);
}

.pat-at-btn--sm {
  padding: 7px 14px;
  font-size: 12px;
}

.pat-at-uh-row {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 12px 0;
  border-bottom: 1px solid var(--border);
  font-size: 13px;
}

.pat-at-uh-row:last-child {
  border-bottom: none;
}

.pat-at-uh-ic {
  width: 34px;
  height: 34px;
  border-radius: 9px;
  background: var(--surface-3);
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}

.pat-at-uh-ic svg {
  width: 16px;
  height: 16px;
  color: var(--patra-3);
}

.pat-at-uh-info {
  flex: 1;
  min-width: 0;
}

.pat-at-uh-un {
  font-weight: 500;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.pat-at-uh-um {
  font-size: 11px;
  color: var(--text-3);
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  margin-top: 1px;
}

.pat-at-uh-tag {
  font-size: 10px;
  font-weight: 600;
  padding: 3px 9px;
  border-radius: 20px;
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  flex-shrink: 0;
}

.pat-at-uh-tag--completed {
  background: rgba(63, 185, 80, 0.16);
  color: var(--green);
}

.pat-at-uh-tag--pending,
.pat-at-uh-tag--queued {
  background: rgba(227, 160, 8, 0.16);
  color: var(--amber);
}

.pat-at-uh-tag--processing {
  background: rgba(88, 166, 255, 0.16);
  color: var(--blue);
}

.pat-at-uh-tag--failed,
.pat-at-uh-tag--rejected {
  background: rgba(248, 81, 73, 0.16);
  color: var(--red);
}

.pat-at-uh-tag--default {
  background: var(--surface-3);
  color: var(--text-3);
}

.pat-at-rq {
  background: var(--canvas);
  border: 1px solid var(--border);
  border-radius: 13px;
  padding: 15px;
  margin-bottom: 13px;
  transition: all 0.25s;
  animation: pat-at-m-in 0.5s cubic-bezier(0.23, 1, 0.32, 1) backwards;
}

.pat-at-rq:hover {
  border-color: var(--border-hi);
  transform: translateY(-2px);
  box-shadow: 0 10px 24px rgba(0, 0, 0, 0.3);
}

.pat-at-rq-top {
  display: flex;
  align-items: center;
  gap: 9px;
  margin-bottom: 11px;
  font-size: 12px;
  color: var(--text-3);
  flex-wrap: wrap;
}

.pat-at-rq-meta {
  font-weight: 600;
  color: var(--text-2);
}

.pat-at-rq-stub {
  font-size: 11px;
  color: var(--patra-3);
  background: transparent;
  border: none;
  cursor: pointer;
  padding: 0;
  text-decoration: underline;
  text-underline-offset: 2px;
}

.pat-at-rq-stub:hover {
  color: var(--patra-2);
}

.pat-at-rq-time {
  margin-left: auto;
  font-family: 'JetBrains Mono', ui-monospace, monospace;
}

.pat-at-rq-msg {
  font-size: 13px;
  line-height: 1.5;
  padding: 10px 13px;
  border-radius: 10px;
  margin-bottom: 8px;
  white-space: pre-wrap;
}

.pat-at-rq-msg--cust {
  background: var(--surface-2);
  border: 1px solid var(--border);
}

.pat-at-rq-msg--agent {
  background: linear-gradient(
    135deg,
    rgba(110, 86, 207, 0.12),
    rgba(139, 92, 246, 0.04)
  );
  border: 1px solid rgba(139, 92, 246, 0.28);
}

.pat-at-rq-ml {
  font-size: 10px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  font-family: 'JetBrains Mono', ui-monospace, monospace;
  margin-bottom: 5px;
  display: block;
}

.pat-at-rq-msg--cust .pat-at-rq-ml {
  color: var(--text-4);
}

.pat-at-rq-msg--agent .pat-at-rq-ml {
  color: var(--patra-3);
}

.pat-at-rq-actions {
  display: flex;
  gap: 9px;
  margin-top: 11px;
}

.pat-at-rq-btn {
  font-size: 12.5px;
  font-weight: 600;
  padding: 8px 16px;
  border-radius: 9px;
  cursor: pointer;
  border: 1px solid var(--border-hi);
  background: var(--surface-2);
  color: var(--text);
  transition: all 0.2s;
}

.pat-at-rq-btn:hover:not(:disabled) {
  transform: translateY(-2px) scale(1.02);
}

.pat-at-rq-btn:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}

.pat-at-rq-btn--approve {
  background: linear-gradient(135deg, var(--green), #2a7f37);
  color: #fff;
  border-color: transparent;
}

.pat-at-rq-btn--discard {
  color: var(--text-3);
}

.pat-at-rq-btn--discard:hover:not(:disabled) {
  color: var(--red);
  border-color: rgba(248, 81, 73, 0.3);
}

.pat-at-sp-form {
  background: var(--canvas);
  border: 1px solid var(--border);
  border-radius: 13px;
  padding: 17px;
}

.pat-at-sp-field {
  margin-bottom: 14px;
}

.pat-at-sp-field label {
  display: block;
  font-size: 12px;
  color: var(--text-2);
  margin-bottom: 6px;
}

.pat-at-sp-field input {
  width: 100%;
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 10px;
  padding: 10px 13px;
  color: var(--text);
  font-size: 13px;
  outline: none;
  transition: all 0.25s;
}

.pat-at-sp-field input:focus {
  border-color: var(--patra);
  box-shadow: 0 0 0 3px rgba(110, 86, 207, 0.11);
}

.pat-at-sp-actions-row {
  display: flex;
  align-items: flex-end;
  gap: 14px;
  flex-wrap: wrap;
}

.pat-at-sp-action-label {
  display: block;
  font-size: 12px;
  color: var(--text-2);
  margin-bottom: 6px;
}

.pat-at-sp-radio {
  display: flex;
  gap: 9px;
  flex-wrap: wrap;
}

.pat-at-sp-radio--compact {
  margin: 8px 0;
}

.pat-at-sp-opt {
  display: flex;
  align-items: center;
  gap: 7px;
  font-size: 12.5px;
  padding: 9px 13px;
  border: 1px solid var(--border);
  border-radius: 10px;
  cursor: pointer;
  transition: all 0.2s;
  background: var(--surface);
  color: var(--text);
}

.pat-at-sp-opt:hover {
  border-color: var(--border-hi);
}

.pat-at-sp-opt--sel {
  border-color: var(--patra);
  background: rgba(110, 86, 207, 0.08);
  color: var(--patra-3);
}

.pat-at-sp-opt--danger.pat-at-sp-opt--sel {
  border-color: var(--red);
  background: rgba(248, 81, 73, 0.08);
  color: var(--red);
}

.pat-at-sp-rd {
  width: 15px;
  height: 15px;
  border-radius: 50%;
  border: 1.5px solid var(--border-hi);
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}

.pat-at-sp-opt--sel .pat-at-sp-rd {
  border-color: var(--patra);
}

.pat-at-sp-opt--sel .pat-at-sp-rd::after {
  content: '';
  width: 7px;
  height: 7px;
  border-radius: 50%;
  background: var(--patra-2);
}

.pat-at-sp-opt--danger.pat-at-sp-opt--sel .pat-at-sp-rd {
  border-color: var(--red);
}

.pat-at-sp-opt--danger.pat-at-sp-opt--sel .pat-at-sp-rd::after {
  background: var(--red);
}

.pat-at-sp-active {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 12.5px;
  color: var(--text-2);
  cursor: pointer;
  white-space: nowrap;
}

.pat-at-sp-active--inline {
  margin-top: 4px;
}

.pat-at-sp-add {
  margin-left: auto;
}

.pat-at-sp-row {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 13px 0;
  border-bottom: 1px solid var(--border);
  flex-wrap: wrap;
}

.pat-at-sp-row:last-child {
  border-bottom: none;
}

.pat-at-sp-phrase {
  flex: 1;
  min-width: 120px;
  font-size: 13.5px;
  font-weight: 500;
  font-family: 'JetBrains Mono', ui-monospace, monospace;
}

.pat-at-sp-act {
  font-size: 11px;
  font-weight: 600;
  padding: 4px 10px;
  border-radius: 20px;
  font-family: 'JetBrains Mono', ui-monospace, monospace;
}

.pat-at-sp-act--notify {
  background: rgba(88, 166, 255, 0.16);
  color: var(--blue);
}

.pat-at-sp-act--pause {
  background: rgba(248, 81, 73, 0.16);
  color: var(--red);
}

.pat-at-sp-triggers {
  font-size: 10px;
  color: var(--text-4);
}

.pat-at-sp-sw {
  width: 34px;
  height: 19px;
  border-radius: 11px;
  background: linear-gradient(135deg, var(--patra), var(--patra-2));
  position: relative;
  cursor: pointer;
  box-shadow: 0 0 10px var(--patra-glow);
  transition: all 0.25s;
  border: none;
  flex-shrink: 0;
  padding: 0;
}

.pat-at-sp-sw i {
  position: absolute;
  top: 2px;
  right: 2px;
  width: 15px;
  height: 15px;
  border-radius: 50%;
  background: #fff;
  transition: all 0.25s;
  display: block;
}

.pat-at-sp-sw--off {
  background: var(--surface-4);
  box-shadow: none;
}

.pat-at-sp-sw--off i {
  right: auto;
  left: 2px;
}

.pat-at-sp-edit-link {
  font-size: 11px;
  color: var(--patra-3);
  background: transparent;
  border: none;
  cursor: pointer;
  padding: 0;
}

.pat-at-sp-edit-link:hover {
  color: var(--patra-2);
  text-decoration: underline;
}

.pat-at-sp-del {
  color: var(--text-4);
  cursor: pointer;
  transition: all 0.2s;
  background: transparent;
  border: none;
  font-size: 14px;
  padding: 0;
  line-height: 1;
}

.pat-at-sp-del:hover {
  color: var(--red);
  transform: scale(1.15);
}

.pat-at-sp-edit {
  width: 100%;
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.pat-at-sp-edit-input {
  width: 100%;
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 10px;
  padding: 8px 12px;
  color: var(--text);
  font-size: 13px;
}

.pat-at-sp-edit-actions {
  display: flex;
  gap: 8px;
}

@keyframes pat-at-m-in {
  from {
    opacity: 0;
    transform: translateY(16px);
  }

  to {
    opacity: 1;
    transform: translateY(0);
  }
}

@keyframes pat-at-fade-in {
  from {
    opacity: 0;
    transform: translateY(8px);
  }

  to {
    opacity: 1;
    transform: translateY(0);
  }
}

@keyframes pat-at-mesh-a {
  0% {
    transform: translate(0, 0) scale(1);
  }

  100% {
    transform: translate(-50px, 40px) scale(1.12) rotate(8deg);
  }
}

@keyframes pat-at-mesh-b {
  0% {
    transform: translate(0, 0) scale(1);
  }

  100% {
    transform: translate(40px, -30px) scale(1.1);
  }
}

@media (max-width: 768px) {
  .pat-at-rag-stats {
    grid-template-columns: repeat(2, 1fr);
  }

  .pat-at-tabs {
    flex-wrap: wrap;
  }

  .pat-at-sp-add {
    margin-left: 0;
    width: 100%;
  }
}

@media (prefers-reduced-motion: reduce) {
  .pat-at-mesh::before,
  .pat-at-mesh::after,
  .pat-at-card,
  .pat-at-rag,
  .pat-at-rq,
  .pat-at-pane {
    animation: none !important;
  }
}
</style>
