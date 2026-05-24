<script setup>
import { onMounted, ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import BroadcastsAPI from 'dashboard/api/broadcasts';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const broadcast = ref({
  name: '',
  channel: 'facebook',
  content: '',
  segment_filter: {},
});
const previewCount = ref(null);
const sending = ref(false);

const load = async () => {
  if (!route.params.broadcastId) return;
  const { data } = await BroadcastsAPI.show(route.params.broadcastId);
  broadcast.value = data;
};

const save = async () => {
  if (route.params.broadcastId) {
    await BroadcastsAPI.update(route.params.broadcastId, broadcast.value);
  } else {
    const { data } = await BroadcastsAPI.create(broadcast.value);
    router.replace({ name: 'patra_broadcast_compose', params: { broadcastId: data.id } });
  }
};

const loadPreviewCount = async () => {
  if (!route.params.broadcastId) return;
  const { data } = await BroadcastsAPI.previewCount(route.params.broadcastId);
  previewCount.value = data.count;
};

const sendNow = async () => {
  sending.value = true;
  await BroadcastsAPI.sendNow(route.params.broadcastId);
  sending.value = false;
  router.push({ name: 'patra_broadcast_list' });
};

onMounted(async () => {
  await load();
  await loadPreviewCount();
});
</script>

<template>
  <div class="flex flex-col gap-4 p-6 max-w-2xl">
    <h1 class="text-2xl font-semibold">{{ $t('PATRA.BROADCASTS.COMPOSE') }}</h1>

    <input
      v-model="broadcast.name"
      class="p-2 border rounded-lg border-n-weak"
      :placeholder="$t('PATRA.BROADCASTS.NAME')"
    />

    <select v-model="broadcast.channel" class="p-2 border rounded-lg border-n-weak">
      <option value="facebook">Facebook</option>
      <option value="instagram">Instagram</option>
      <option value="sms">SMS</option>
      <option value="email">Email</option>
      <option value="whatsapp">WhatsApp</option>
    </select>

    <textarea
      v-model="broadcast.content"
      class="p-2 border rounded-lg border-n-weak"
      rows="6"
      :placeholder="$t('PATRA.BROADCASTS.CONTENT')"
    />

    <p v-if="previewCount !== null" class="text-sm text-n-slate-11">
      {{ $t('PATRA.BROADCASTS.MATCHING_CONTACTS', { count: previewCount }) }}
    </p>

    <div class="flex gap-2">
      <button class="px-3 py-2 text-sm rounded-lg border border-n-weak" @click="save">
        {{ $t('PATRA.BROADCASTS.SAVE') }}
      </button>
      <button
        v-if="route.params.broadcastId"
        class="px-3 py-2 text-sm text-white rounded-lg bg-n-brand"
        :disabled="sending"
        @click="sendNow"
      >
        {{ $t('PATRA.BROADCASTS.SEND_NOW') }}
      </button>
    </div>
  </div>
</template>
