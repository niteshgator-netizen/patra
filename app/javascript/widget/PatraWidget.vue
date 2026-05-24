<script setup>
import { onMounted, ref } from 'vue';

const props = defineProps({
  websiteToken: { type: String, required: true },
  businessName: { type: String, default: 'Support' },
});

const open = ref(false);
const messages = ref([]);
const input = ref('');
const prechat = ref({ name: '', email: '', question: '' });
const showPrechat = ref(true);

const sendMessage = async () => {
  if (!input.value.trim()) return;
  const response = await fetch('/widget/patra/messages', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      website_token: props.websiteToken,
      content: input.value,
      name: prechat.value.name,
      email: prechat.value.email,
    }),
  });
  const data = await response.json();
  messages.value.push({ content: input.value, outgoing: true });
  input.value = '';
  if (data.message_id) {
    messages.value.push({ content: 'Thanks! An agent will respond shortly.', outgoing: false });
  }
};

const startChat = () => {
  showPrechat.value = false;
};
</script>

<template>
  <div class="fixed bottom-4 right-4 z-50 font-sans">
    <button
      v-if="!open"
      class="px-4 py-3 text-white rounded-full shadow-lg bg-n-brand"
      @click="open = true"
    >
      Chat with {{ businessName }}
    </button>

    <div v-else class="flex flex-col w-80 h-96 bg-white rounded-xl shadow-2xl">
      <header class="flex items-center justify-between px-4 py-3 text-white rounded-t-xl bg-n-brand">
        <span>{{ businessName }}</span>
        <button @click="open = false">✕</button>
      </header>

      <div v-if="showPrechat" class="flex flex-col flex-1 gap-2 p-4">
        <input v-model="prechat.name" class="p-2 border rounded-lg" placeholder="Name" />
        <input v-model="prechat.email" class="p-2 border rounded-lg" placeholder="Email" />
        <textarea v-model="prechat.question" class="p-2 border rounded-lg" placeholder="Your question" rows="3" />
        <button class="py-2 text-white rounded-lg bg-n-brand" @click="startChat">Start Chat</button>
      </div>

      <template v-else>
        <div class="flex-1 p-3 overflow-y-auto">
          <div
            v-for="(msg, i) in messages"
            :key="i"
            class="mb-2 text-sm"
            :class="msg.outgoing ? 'text-right' : 'text-left'"
          >
            <span
              class="inline-block px-3 py-1 rounded-lg"
              :class="msg.outgoing ? 'bg-n-brand text-white' : 'bg-gray-100'"
            >
              {{ msg.content }}
            </span>
          </div>
        </div>
        <div class="flex gap-2 p-3 border-t">
          <input v-model="input" class="flex-1 p-2 text-sm border rounded-lg" @keyup.enter="sendMessage" />
          <button class="px-3 text-white rounded-lg bg-n-brand" @click="sendMessage">Send</button>
        </div>
      </template>
    </div>
  </div>
</template>
