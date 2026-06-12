<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import PatraAgentFeedbackAPI from 'dashboard/api/patraAgentFeedback';

const CATEGORIES = [
  { value: 'bug', label: 'Bug' },
  { value: 'player_issue', label: 'Player issue' },
  { value: 'suggestion', label: 'Suggestion' },
  { value: 'other', label: 'Other' },
];

const route = useRoute();
const { accountScopedUrl } = useAccount();
const currentRole = useMapGetter('getCurrentRole');
const isAdmin = computed(() => currentRole.value === 'administrator');

const feedbacks = ref([]);
const loading = ref(true);
const sending = ref(false);
const updating = ref(null);

// Admin filters
const categoryFilter = ref('');
const statusFilter = ref('');

// Agent form — conversation/contact context pre-filled from query params
// (the conversation header's "Send feedback" action sets them).
const form = ref({
  body: '',
  category: 'other',
  conversation_id: route.query.conversation_id || '',
  contact_id: route.query.contact_id || '',
});

const loadFeedbacks = async () => {
  loading.value = true;
  try {
    const params = {};
    if (categoryFilter.value) params.category = categoryFilter.value;
    if (statusFilter.value) params.status = statusFilter.value;
    const res = await PatraAgentFeedbackAPI.list(params);
    feedbacks.value = res.data || [];
  } catch {
    useAlert('Failed to load feedback');
  } finally {
    loading.value = false;
  }
};

onMounted(loadFeedbacks);

const sendFeedback = async () => {
  if (!form.value.body.trim()) {
    useAlert('Write something first');
    return;
  }
  sending.value = true;
  try {
    await PatraAgentFeedbackAPI.create({
      body: form.value.body.trim(),
      category: form.value.category,
      conversation_id: form.value.conversation_id || undefined,
      contact_id: form.value.contact_id || undefined,
    });
    useAlert('Feedback sent to the owner');
    form.value.body = '';
    form.value.conversation_id = '';
    form.value.contact_id = '';
    await loadFeedbacks();
  } catch {
    useAlert('Failed to send feedback');
  } finally {
    sending.value = false;
  }
};

const setStatus = async (feedback, status) => {
  updating.value = feedback.id;
  try {
    await PatraAgentFeedbackAPI.setStatus(feedback.id, status);
    feedback.status = status;
  } catch {
    useAlert('Failed to update status');
  } finally {
    updating.value = null;
  }
};

const categoryLabel = value =>
  CATEGORIES.find(c => c.value === value)?.label || value;

const conversationUrl = displayId =>
  accountScopedUrl(`conversations/${displayId}`);

const contactUrl = id => accountScopedUrl(`contacts/${id}`);

const formatTime = value => (value ? new Date(value).toLocaleString() : '—');
</script>

<template>
  <div class="flex flex-col gap-6 p-6 overflow-y-auto w-full">
    <header>
      <h2 class="text-2xl font-semibold text-n-slate-12">
        {{ isAdmin ? 'Agent Feedback' : 'Send Feedback' }}
      </h2>
      <p class="text-sm text-n-slate-11">
        {{
          isAdmin
            ? 'What your agents are reporting — bugs, player issues, ideas. Newest first.'
            : 'Spotted a bug or a player problem? Tell the owner — only admins see this, never players.'
        }}
      </p>
    </header>

    <!-- Agent: send form -->
    <section
      v-if="!isAdmin"
      class="max-w-xl rounded-xl border border-n-weak bg-n-solid-1 p-4 flex flex-col gap-3"
    >
      <form class="flex flex-col gap-3" @submit.prevent="sendFeedback">
        <label class="block">
          <span class="text-xs text-n-slate-11">Category</span>
          <select
            v-model="form.category"
            class="w-full mt-1 p-2 rounded-lg bg-n-alpha-2 border border-n-weak text-sm text-n-slate-12"
          >
            <option v-for="c in CATEGORIES" :key="c.value" :value="c.value">
              {{ c.label }}
            </option>
          </select>
        </label>
        <label class="block">
          <span class="text-xs text-n-slate-11">What happened?</span>
          <textarea
            v-model="form.body"
            rows="4"
            required
            placeholder="Describe the bug, player issue, or idea…"
            class="w-full mt-1 p-2 rounded-lg bg-n-alpha-2 border border-n-weak text-sm text-n-slate-12"
          />
        </label>
        <p v-if="form.conversation_id" class="text-xs text-n-slate-11">
          Attached to conversation #{{ form.conversation_id }}
        </p>
        <button
          type="submit"
          :disabled="sending"
          class="self-start px-4 py-2 rounded-lg bg-n-brand text-white text-sm font-medium disabled:opacity-50"
        >
          {{ sending ? 'Sending…' : 'Send feedback' }}
        </button>
      </form>
    </section>

    <!-- Admin: filters -->
    <div v-if="isAdmin" class="flex gap-3">
      <select
        v-model="categoryFilter"
        class="p-2 rounded-lg bg-n-alpha-2 border border-n-weak text-sm text-n-slate-12"
        @change="loadFeedbacks"
      >
        <option value="">All categories</option>
        <option v-for="c in CATEGORIES" :key="c.value" :value="c.value">
          {{ c.label }}
        </option>
      </select>
      <select
        v-model="statusFilter"
        class="p-2 rounded-lg bg-n-alpha-2 border border-n-weak text-sm text-n-slate-12"
        @change="loadFeedbacks"
      >
        <option value="">All statuses</option>
        <option value="new">New</option>
        <option value="seen">Seen</option>
      </select>
    </div>

    <div v-if="loading" class="text-sm text-n-slate-11">Loading…</div>

    <p
      v-else-if="feedbacks.length === 0"
      class="rounded-xl border border-n-weak bg-n-solid-1 py-12 text-center text-sm text-n-slate-11"
    >
      {{
        isAdmin
          ? 'No feedback yet. Entries appear here the moment an agent sends one.'
          : 'Nothing sent yet. Your feedback will show up here after you send it.'
      }}
    </p>

    <section v-else class="flex flex-col gap-3">
      <h3 v-if="!isAdmin" class="text-sm font-semibold text-n-slate-12">
        Your feedback
      </h3>
      <article
        v-for="feedback in feedbacks"
        :key="feedback.id"
        class="rounded-xl border border-n-weak bg-n-solid-1 p-4 flex flex-col gap-2"
      >
        <div class="flex items-center gap-2 flex-wrap">
          <span
            class="px-2 py-0.5 rounded-full text-xs font-medium bg-n-alpha-2 text-n-slate-11"
          >
            {{ categoryLabel(feedback.category) }}
          </span>
          <span
            class="px-2 py-0.5 rounded-full text-xs font-medium"
            :class="
              feedback.status === 'new'
                ? 'bg-n-brand/10 text-n-brand'
                : 'bg-n-alpha-2 text-n-slate-10'
            "
          >
            {{ feedback.status === 'new' ? 'New' : 'Seen' }}
          </span>
          <span class="text-xs text-n-slate-10 ml-auto">
            {{ formatTime(feedback.created_at) }}
          </span>
        </div>
        <p class="text-sm text-n-slate-12 whitespace-pre-wrap m-0">
          {{ feedback.body }}
        </p>
        <div class="flex items-center gap-3 text-xs text-n-slate-11 flex-wrap">
          <span v-if="isAdmin && feedback.user">
            From {{ feedback.user.name }}
          </span>
          <a
            v-if="feedback.conversation_display_id"
            :href="conversationUrl(feedback.conversation_display_id)"
            class="text-n-brand"
          >
            Conversation #{{ feedback.conversation_display_id }}
          </a>
          <a
            v-if="feedback.contact"
            :href="contactUrl(feedback.contact.id)"
            class="text-n-brand"
          >
            {{ feedback.contact.name || 'Contact' }}
          </a>
          <button
            v-if="isAdmin"
            type="button"
            :disabled="updating === feedback.id"
            class="ml-auto px-3 py-1 rounded-lg border border-n-weak text-xs font-medium text-n-slate-12 disabled:opacity-50"
            @click="
              setStatus(feedback, feedback.status === 'new' ? 'seen' : 'new')
            "
          >
            {{ feedback.status === 'new' ? 'Mark seen' : 'Mark new' }}
          </button>
        </div>
      </article>
    </section>
  </div>
</template>
