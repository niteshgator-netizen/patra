<script>
import ReplyPreferencesAPI from '../../../../api/replyPreferences';
import { useAlert } from 'dashboard/composables';

export default {
  data() {
    return {
      pref: {
        reply_tone: 'casual',
        use_emojis: true,
        max_reply_lines: 2,
        sign_off_text: '',
        use_rag_examples: true,
        rag_example_count: 3,
        confirm_before_load: false,
        confirm_before_cashout: true,
        auto_send_receipt: true,
        memory_enabled: true,
      },
      loading: true,
    };
  },
  mounted() {
    this.fetchPref();
  },
  methods: {
    async fetchPref() {
      try {
        const accountId = this.$route.params.accountId;
        const { data } =
          await ReplyPreferencesAPI.getReplyPreference(accountId);
        this.pref = { ...this.pref, ...data };
      } catch (e) {
        console.error('Failed to fetch reply preferences:', e);
      } finally {
        this.loading = false;
      }
    },
    async save() {
      try {
        const accountId = this.$route.params.accountId;
        await ReplyPreferencesAPI.updateReplyPreference(accountId, this.pref);
        useAlert('Reply style saved');
      } catch (e) {
        useAlert('Failed to save');
        console.error(e);
      }
    },
  },
};
</script>

<template>
  <div class="pat-tpage flex-1 overflow-auto p-6">
    <div class="max-w-2xl">
      <h2 class="text-lg font-medium mb-4">Reply Style</h2>
      <p class="text-sm text-slate-400 mb-6">
        Control how Bella replies to customers.
      </p>

      <div v-if="loading" class="flex flex-col gap-3">
        <div v-for="n in 4" :key="n" class="pat-skel h-10 w-full" />
      </div>

      <div v-else class="space-y-6">
        <label class="block">
          <span class="text-sm">Tone</span>
          <select
            v-model="pref.reply_tone"
            class="w-full mt-1 p-2 bg-slate-800 border border-slate-600 rounded text-sm"
          >
            <option value="casual">Casual (texting on shift)</option>
            <option value="professional">Professional</option>
            <option value="minimal">Minimal</option>
          </select>
        </label>

        <label class="flex items-center gap-2">
          <input v-model="pref.use_emojis" type="checkbox" />
          <span class="text-sm">Use emojis</span>
        </label>

        <label class="block">
          <span class="text-sm">Max reply lines</span>
          <input
            v-model.number="pref.max_reply_lines"
            type="number"
            min="1"
            max="10"
            class="w-24 mt-1 p-2 bg-slate-800 border border-slate-600 rounded text-sm"
          />
        </label>

        <label class="block">
          <span class="text-sm">Sign-off text</span>
          <input
            v-model="pref.sign_off_text"
            type="text"
            placeholder="e.g. - Bella, xo, etc."
            class="w-full mt-1 p-2 bg-slate-800 border border-slate-600 rounded text-sm"
          />
        </label>

        <hr class="border-slate-700" />

        <label class="flex items-center gap-2">
          <input v-model="pref.use_rag_examples" type="checkbox" />
          <span class="text-sm">Use RAG examples for reply style</span>
        </label>

        <label class="block">
          <span class="text-sm">Number of RAG examples</span>
          <input
            v-model.number="pref.rag_example_count"
            type="number"
            min="1"
            max="10"
            class="w-24 mt-1 p-2 bg-slate-800 border border-slate-600 rounded text-sm"
          />
        </label>

        <hr class="border-slate-700" />

        <label class="flex items-center gap-2">
          <input v-model="pref.memory_enabled" type="checkbox" />
          <span class="text-sm"
            >Remember each player (AI builds a memory of who they are)</span
          >
        </label>
        <p class="text-xs text-slate-500 -mt-2 leading-relaxed">
          Recent messages always stay word-for-word. Older history is distilled
          into a short per-player memory — who they are, their style, attitude.
          You can view or edit it on each contact in the conversation panel.
          Turn this off to stop building and using player memory.
        </p>

        <hr class="border-slate-700" />

        <label class="flex items-center gap-2">
          <input v-model="pref.confirm_before_load" type="checkbox" />
          <span class="text-sm">Confirm before loading credits</span>
        </label>

        <label class="flex items-center gap-2">
          <input v-model="pref.confirm_before_cashout" type="checkbox" />
          <span class="text-sm">Confirm before cashout</span>
        </label>

        <label class="flex items-center gap-2">
          <input v-model="pref.auto_send_receipt" type="checkbox" />
          <span class="text-sm">Auto-send receipt after load</span>
        </label>

        <button
          class="px-4 py-2 bg-indigo-600 hover:bg-indigo-500 rounded text-sm font-medium"
          @click="save"
        >
          Save
        </button>
      </div>
    </div>
  </div>
</template>
