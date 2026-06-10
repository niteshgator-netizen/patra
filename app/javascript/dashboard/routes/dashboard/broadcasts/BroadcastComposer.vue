<script setup>
import { onMounted, ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
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
  try {
    const { data } = await BroadcastsAPI.show(route.params.broadcastId);
    broadcast.value = data;
  } catch (error) {
    useAlert(t('PATRA.BROADCASTS.LOAD_ERROR'));
  }
};

const save = async () => {
  try {
    if (route.params.broadcastId) {
      await BroadcastsAPI.update(route.params.broadcastId, broadcast.value);
    } else {
      const { data } = await BroadcastsAPI.create(broadcast.value);
      router.replace({
        name: 'patra_broadcast_compose',
        params: { broadcastId: data.id },
      });
    }
  } catch (error) {
    useAlert(t('PATRA.BROADCASTS.SAVE_ERROR'));
  }
};

const loadPreviewCount = async () => {
  if (!route.params.broadcastId) return;
  try {
    const { data } = await BroadcastsAPI.previewCount(route.params.broadcastId);
    previewCount.value = data.count;
  } catch (error) {
    previewCount.value = null;
  }
};

const sendNow = async () => {
  sending.value = true;
  try {
    await BroadcastsAPI.sendNow(route.params.broadcastId);
    router.push({ name: 'patra_broadcast_list' });
  } catch (error) {
    useAlert(t('PATRA.BROADCASTS.SEND_ERROR'));
  } finally {
    // Always reset so the Send button can't stay stuck on "Sending…".
    sending.value = false;
  }
};

onMounted(async () => {
  await load();
  await loadPreviewCount();
});
</script>

<template>
  <div class="pat-page-wrap">
    <div class="pat-page-main">
      <div class="flex flex-col gap-4 p-6">
        <h1 class="text-2xl font-semibold">
          {{ $t('PATRA.BROADCASTS.COMPOSE') }}
        </h1>

        <div class="bc-grid">
          <section class="bc-card">
            <div class="bc-card-h">
              <span class="bc-dot" />
              {{ $t('PATRA.BROADCASTS.COMPOSE') }}
            </div>

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
          </section>

          <section class="bc-card">
            <div class="bc-card-h">
              <span class="bc-dot" />
              {{ $t('PATRA.BROADCASTS.PREVIEW') }}
            </div>
            <div class="bc-preview">
              <div class="bc-preview-row">
                <div class="bc-preview-ava">P</div>
                <div class="bc-preview-bubble" :class="{ empty: !broadcast.content }">
                  {{ broadcast.content || $t('PATRA.BROADCASTS.PREVIEW_EMPTY') }}
                </div>
              </div>
              <p v-if="previewCount !== null" class="bc-preview-count">
                {{
                  $t('PATRA.BROADCASTS.MATCHING_CONTACTS', {
                    count: previewCount,
                  })
                }}
              </p>
            </div>
          </section>
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

/* B5: spec Broadcast Composer two-card layout (Message + Preview) */
.bc-grid {
  display: grid;
  grid-template-columns: minmax(0, 1.2fr) minmax(0, 1fr);
  gap: 16px;
  max-width: 1100px;
}

@media (max-width: 900px) {
  .bc-grid {
    grid-template-columns: 1fr;
  }
}

.bc-card {
  display: flex;
  flex-direction: column;
  gap: 12px;
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 16px;
  padding: 20px;
}

.bc-card-h {
  display: flex;
  align-items: center;
  gap: 9px;
  font-family: 'Space Grotesk', sans-serif;
  font-weight: 600;
  font-size: 15px;
}

.bc-dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: var(--patra-3, #a78bfa);
  box-shadow: 0 0 8px rgba(110, 86, 207, 0.4);
}

.bc-preview {
  background: var(--surface-2);
  border: 1px solid var(--border);
  border-radius: 12px;
  padding: 18px;
  min-height: 200px;
  display: flex;
  flex-direction: column;
}

.bc-preview-row {
  display: flex;
  gap: 10px;
  margin-bottom: 12px;
}

.bc-preview-ava {
  width: 28px;
  height: 28px;
  border-radius: 50%;
  flex-shrink: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  font-weight: 700;
  font-size: 12px;
  color: #fff;
  background: linear-gradient(135deg, var(--patra), #5b45b0);
}

.bc-preview-bubble {
  background: var(--surface-3);
  padding: 10px 14px;
  border-radius: 14px 14px 14px 4px;
  font-size: 13px;
  max-width: 80%;
  white-space: pre-wrap;
  word-break: break-word;
}

.bc-preview-bubble.empty {
  color: var(--text-4);
}

.bc-preview-count {
  color: var(--text-4);
  font-size: 12px;
  text-align: center;
  margin-top: auto;
  padding-top: 20px;
}
</style>
