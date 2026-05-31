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
    router.replace({
      name: 'patra_broadcast_compose',
      params: { broadcastId: data.id },
    });
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
  <div class="pat-page-wrap">
    <div class="pat-page-main">
      <div class="flex flex-col gap-4 p-6 max-w-2xl">
        <h1 class="text-2xl font-semibold">
          {{ $t('PATRA.BROADCASTS.COMPOSE') }}
        </h1>

        <input
          v-model="broadcast.name"
          class="p-2 border rounded-lg border-n-weak"
          :placeholder="$t('PATRA.BROADCASTS.NAME')"
        />

        <select
          v-model="broadcast.channel"
          class="p-2 border rounded-lg border-n-weak"
        >
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
          {{
            $t('PATRA.BROADCASTS.MATCHING_CONTACTS', { count: previewCount })
          }}
        </p>

        <div class="flex gap-2">
          <button
            class="px-3 py-2 text-sm rounded-lg border border-n-weak"
            @click="save"
          >
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
    </div>
  </div>
</template>

<style scoped>
.pat-page-wrap {
  --canvas: #050409;
  --surface: #0c0b12;
  --surface-2: #131119;
  --surface-3: #1b1925;
  --surface-4: #252233;
  --border: #171520;
  --border-hi: #2e2940;
  --patra: #6e56cf;
  --patra-3: #a78bfa;
  --text: #ededf2;
  --text-2: #a8a6b6;
  --text-3: #75727f;
  --text-4: #54515e;
  --green: #3fb950;
  --red: #f85149;

  position: relative;
  min-height: 100%;
  margin-left: -24px;
  margin-right: -24px;
  padding: 0 24px 24px;
  color: var(--text);
  font-family: 'Inter', sans-serif;
  background: var(--canvas);
}

.pat-page-main {
  position: relative;
  z-index: 1;
}

.pat-page-wrap :deep(.text-heading-1),
.pat-page-wrap :deep(h1),
.pat-page-wrap :deep(h2) {
  color: var(--text) !important;
}

.pat-page-wrap :deep(.text-n-slate-12) {
  color: var(--text) !important;
}

.pat-page-wrap :deep(.text-n-slate-11) {
  color: var(--text-2) !important;
}

.pat-page-wrap :deep(.text-n-slate-10),
.pat-page-wrap :deep(.text-n-slate-9) {
  color: var(--text-3) !important;
}

.pat-page-wrap :deep(.text-n-slate-6),
.pat-page-wrap :deep(.text-n-slate-7),
.pat-page-wrap :deep(.text-n-slate-8) {
  color: var(--text-4) !important;
}

.pat-page-wrap :deep(.bg-n-surface-1),
.pat-page-wrap :deep(.bg-n-solid-1) {
  background: var(--canvas) !important;
}

.pat-page-wrap :deep(.bg-n-surface-2),
.pat-page-wrap :deep(.bg-n-solid-2),
.pat-page-wrap :deep(.bg-n-solid-3) {
  background: var(--surface) !important;
}

.pat-page-wrap :deep(.bg-n-alpha-1),
.pat-page-wrap :deep(.bg-n-alpha-2) {
  background: var(--surface-2) !important;
}

.pat-page-wrap :deep(.bg-n-slate-1),
.pat-page-wrap :deep(.bg-n-slate-2) {
  background: var(--surface-2) !important;
}

.pat-page-wrap :deep(.bg-n-slate-3) {
  background: var(--surface-3) !important;
}

.pat-page-wrap :deep(.rounded-xl.border),
.pat-page-wrap :deep(.rounded-lg.border) {
  border-color: var(--border) !important;
}

.pat-page-wrap :deep(.border-n-weak),
.pat-page-wrap :deep(.border-n-container),
.pat-page-wrap :deep(.outline-n-weak),
.pat-page-wrap :deep(.outline-n-container),
.pat-page-wrap :deep(.dark\:border-n-slate-6) {
  border-color: var(--border) !important;
  outline-color: var(--border) !important;
}

.pat-page-wrap :deep(.divide-y > *) {
  border-color: var(--border) !important;
}

.pat-page-wrap :deep(.group-hover\:bg-n-alpha-2) {
  background: var(--surface-2) !important;
  border-color: var(--border-hi) !important;
  color: var(--text-2) !important;
}

.pat-page-wrap :deep(.group:hover .group-hover\:bg-n-alpha-2) {
  background: var(--surface-3) !important;
  border-color: var(--patra) !important;
  color: var(--text) !important;
}

.pat-page-wrap :deep(thead) {
  background: var(--surface-2) !important;
}

.pat-page-wrap :deep(thead th) {
  color: var(--text-4) !important;
  border-bottom: 1px solid var(--border);
}

.pat-page-wrap :deep(tbody tr:hover) {
  background: var(--surface-2) !important;
}

.pat-page-wrap :deep(tbody td) {
  color: var(--text);
  border-color: var(--border);
}

.pat-page-wrap :deep(input),
.pat-page-wrap :deep(textarea),
.pat-page-wrap :deep(select) {
  background: var(--surface-2);
  border: 1px solid var(--border);
  color: var(--text);
  border-radius: 8px;
}

.pat-page-wrap :deep(input:focus),
.pat-page-wrap :deep(textarea:focus),
.pat-page-wrap :deep(select:focus) {
  border-color: var(--patra);
  outline: none;
  box-shadow: 0 0 0 3px rgba(110, 86, 207, 0.11);
}

.pat-page-wrap :deep(.text-n-teal-10),
.pat-page-wrap :deep(.text-n-teal-11) {
  color: var(--green) !important;
}

.pat-page-wrap :deep(.text-n-ruby-9),
.pat-page-wrap :deep(.text-n-ruby-10) {
  color: var(--red) !important;
}

.pat-page-wrap :deep(.fixed.z-50.bg-n-slate-12) {
  background: var(--surface-4) !important;
  border: 1px solid var(--border-hi);
  color: var(--text) !important;
}

.pat-page-wrap :deep(.animate-loader-pulse) {
  background: var(--surface-3) !important;
}
</style>
