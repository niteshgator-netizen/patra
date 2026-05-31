<script setup>
import { useAlert } from 'dashboard/composables';
import AddCanned from './AddCanned.vue';
import EditCanned from './EditCanned.vue';
import CustomBrandPolicyWrapper from 'dashboard/components/CustomBrandPolicyWrapper.vue';
import { getHelpUrlForFeature } from '../../../../helper/featureHelper';
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStoreGetters, useStore } from 'dashboard/composables/store';
import { picoSearch } from '@scmmishra/pico-search';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';

import Icon from 'dashboard/components-next/icon/Icon.vue';
import Button from 'dashboard/components-next/button/Button.vue';

defineOptions({
  name: 'CannedResponseSettings',
});

const getters = useStoreGetters();
const store = useStore();
const { t } = useI18n();

const { getPlainText } = useMessageFormatter();

const showAddPopup = ref(false);
const loading = ref({});
const showEditPopup = ref(false);
const showDeleteConfirmationPopup = ref(false);
const activeResponse = ref({});
const cannedResponseAPI = ref({ message: '' });

const sortOrder = ref('asc');
const searchQuery = ref('');
const spotlight = ref(null);

const helpURL = getHelpUrlForFeature('canned_responses');

const records = computed(() =>
  getters.getSortedCannedResponses.value(sortOrder.value)
);

const filteredRecords = computed(() => {
  const query = searchQuery.value.trim();
  if (!query) return records.value;
  return picoSearch(records.value, query, [
    { name: 'short_code', weight: 4 },
    'content',
  ]);
});
const uiFlags = computed(() => getters.getUIFlags.value);

const deleteConfirmText = computed(
  () =>
    `${t('CANNED_MGMT.DELETE.CONFIRM.YES')} ${activeResponse.value.short_code}`
);

const deleteRejectText = computed(
  () =>
    `${t('CANNED_MGMT.DELETE.CONFIRM.NO')} ${activeResponse.value.short_code}`
);

const deleteMessage = computed(() => {
  return ` ${activeResponse.value.short_code} ? `;
});

const toggleSort = () => {
  sortOrder.value = sortOrder.value === 'asc' ? 'desc' : 'asc';
};

const fetchCannedResponses = async () => {
  try {
    await store.dispatch('getCannedResponse');
  } catch (error) {
    // Ignore Error
  }
};

onMounted(() => {
  fetchCannedResponses();
});

const showAlertMessage = message => {
  loading.value[activeResponse.value.id] = false;
  activeResponse.value = {};
  cannedResponseAPI.value.message = message;
  useAlert(message);
};

const openAddPopup = () => {
  showAddPopup.value = true;
};
const hideAddPopup = () => {
  showAddPopup.value = false;
};

const openEditPopup = response => {
  showEditPopup.value = true;
  activeResponse.value = response;
};
const hideEditPopup = () => {
  showEditPopup.value = false;
};

const openDeletePopup = response => {
  showDeleteConfirmationPopup.value = true;
  activeResponse.value = response;
};

const closeDeletePopup = () => {
  showDeleteConfirmationPopup.value = false;
};

const deleteCannedResponse = async id => {
  try {
    await store.dispatch('deleteCannedResponse', id);
    showAlertMessage(t('CANNED_MGMT.DELETE.API.SUCCESS_MESSAGE'));
  } catch (error) {
    const errorMessage =
      error?.message || t('CANNED_MGMT.DELETE.API.ERROR_MESSAGE');
    showAlertMessage(errorMessage);
  }
};

const confirmDeletion = () => {
  loading.value[activeResponse.value.id] = true;
  closeDeletePopup();
  deleteCannedResponse(activeResponse.value.id);
};

const isLongBody = content => getPlainText(content).length > 180;

const onSpotlightMove = e => {
  const el = spotlight.value;
  if (!el) return;
  el.style.left = `${e.clientX}px`;
  el.style.top = `${e.clientY}px`;
  el.style.opacity = '1';
};

const onSpotlightLeave = () => {
  const el = spotlight.value;
  if (el) el.style.opacity = '0';
};

const onCardGlow = e => {
  const card = e.target.closest('.card');
  if (!card) return;
  const rect = card.getBoundingClientRect();
  card.style.setProperty('--gx', `${e.clientX - rect.left}px`);
  card.style.setProperty('--gy', `${e.clientY - rect.top}px`);
};
</script>

<template>
  <div
    class="pat-canned-wrap"
    @mousemove="onSpotlightMove"
    @mouseleave="onSpotlightLeave"
  >
    <div id="spotlight" ref="spotlight" />
    <div class="mesh" />

    <div class="pat-canned-main" @mousemove="onCardGlow">
      <div class="sec-head">
        <h1 class="display">{{ $t('CANNED_MGMT.HEADER') }}</h1>
        <div class="sub">{{ $t('CANNED_MGMT.DESCRIPTION') }}</div>
        <CustomBrandPolicyWrapper :show-on-custom-branded-instance="false">
          <a
            v-if="helpURL"
            :href="helpURL"
            target="_blank"
            rel="noopener noreferrer"
            class="learn-link"
          >
            {{ $t('CANNED_MGMT.LEARN_MORE') }}
            <Icon icon="i-lucide-chevron-right" class="learn-icon" />
          </a>
        </CustomBrandPolicyWrapper>
      </div>

      <div v-if="uiFlags.fetchingList" class="card">
        <p class="loading-note">{{ $t('CANNED_MGMT.LOADING') }}</p>
      </div>

      <div v-else-if="!records.length" class="card">
        <div class="empty-card">
          <div class="ec-ic">{{ $t('PATRA.SETTINGS.EMPTY_ICON_CANNED') }}</div>
          {{ $t('CANNED_MGMT.LIST.404') }}
          <button
            type="button"
            class="btn primary sm empty-action"
            @click="openAddPopup"
          >
            {{ $t('CANNED_MGMT.HEADER_BTN_TXT') }}
          </button>
        </div>
      </div>

      <div v-else class="card">
        <div class="card-toolbar">
          <input
            v-model="searchQuery"
            type="search"
            class="pat-search"
            :placeholder="$t('CANNED_MGMT.SEARCH_PLACEHOLDER')"
          />
          <button
            type="button"
            class="sort-btn"
            :title="$t('CANNED_MGMT.LIST.TABLE_HEADER.SHORT_CODE')"
            @click="toggleSort"
          >
            <Icon
              class="sort-icon"
              :icon="
                sortOrder === 'desc'
                  ? 'i-woot-sort-descending'
                  : 'i-woot-sort-ascending'
              "
            />
          </button>
          <span v-if="records.length" class="count-label">
            {{ $t('CANNED_MGMT.COUNT', { n: records.length }) }}
          </span>
          <button type="button" class="btn primary sm" @click="openAddPopup">
            {{ $t('CANNED_MGMT.HEADER_BTN_TXT') }}
          </button>
        </div>

        <div v-if="!filteredRecords.length && searchQuery" class="empty-card">
          {{ $t('CANNED_MGMT.NO_RESULTS') }}
        </div>

        <div
          v-for="cannedItem in filteredRecords"
          :key="cannedItem.short_code"
          class="cr"
        >
          <div class="cr-top">
            <span class="cr-code">{{ cannedItem.short_code }}</span>
            <button
              type="button"
              class="cr-edit"
              @click="openEditPopup(cannedItem)"
            >
              {{ $t('CANNED_MGMT.EDIT.BUTTON_TEXT') }}
            </button>
            <Button
              v-tooltip.top="$t('CANNED_MGMT.DELETE.BUTTON_TEXT')"
              icon="i-woot-bin"
              slate
              sm
              class="cr-delete hover:enabled:text-n-ruby-11 hover:enabled:bg-n-ruby-2"
              :is-loading="loading[cannedItem.id]"
              @click="openDeletePopup(cannedItem)"
            />
          </div>
          <p class="cr-body" :class="{ long: isLongBody(cannedItem.content) }">
            {{ getPlainText(cannedItem.content) }}
          </p>
        </div>
      </div>
    </div>

    <woot-modal v-model:show="showAddPopup" :on-close="hideAddPopup">
      <AddCanned :on-close="hideAddPopup" />
    </woot-modal>

    <woot-modal v-model:show="showEditPopup" :on-close="hideEditPopup">
      <EditCanned
        v-if="showEditPopup"
        :id="activeResponse.id"
        :edshort-code="activeResponse.short_code"
        :edcontent="activeResponse.content"
        :on-close="hideEditPopup"
      />
    </woot-modal>

    <woot-delete-modal
      v-model:show="showDeleteConfirmationPopup"
      :on-close="closeDeletePopup"
      :on-confirm="confirmDeletion"
      :title="$t('CANNED_MGMT.DELETE.CONFIRM.TITLE')"
      :message="$t('CANNED_MGMT.DELETE.CONFIRM.MESSAGE')"
      :message-value="deleteMessage"
      :confirm-text="deleteConfirmText"
      :reject-text="deleteRejectText"
    />
  </div>
</template>

<style scoped>
.pat-canned-wrap {
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
  --mesh-1: rgba(110, 86, 207, 0.16);
  --mesh-2: rgba(139, 92, 246, 0.1);
  --mesh-3: rgba(236, 72, 153, 0.05);

  position: relative;
  min-height: 100%;
  color: var(--text);
  font-family: 'Inter', sans-serif;
  background: var(--canvas);
  overflow: hidden;
}

.display {
  font-family: 'Space Grotesk', sans-serif;
}

#spotlight {
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

.mesh {
  position: fixed;
  inset: 0;
  pointer-events: none;
  z-index: 0;
  overflow: hidden;
}

.mesh::before,
.mesh::after {
  content: '';
  position: absolute;
  border-radius: 50%;
  filter: blur(100px);
}

.mesh::before {
  top: -15%;
  right: -5%;
  width: 700px;
  height: 560px;
  background:
    radial-gradient(circle at 40% 40%, var(--mesh-1), transparent 60%),
    radial-gradient(circle at 70% 70%, var(--mesh-2), transparent 60%);
  animation: meshA 22s ease-in-out infinite alternate;
}

.mesh::after {
  bottom: -20%;
  left: 10%;
  width: 560px;
  height: 500px;
  background: radial-gradient(
    circle at 50% 50%,
    var(--mesh-3),
    transparent 65%
  );
  animation: meshB 28s ease-in-out infinite alternate;
}

@keyframes meshA {
  0% {
    transform: translate(0, 0) scale(1);
  }
  100% {
    transform: translate(-50px, 40px) scale(1.12) rotate(8deg);
  }
}

@keyframes meshB {
  0% {
    transform: translate(0, 0) scale(1);
  }
  100% {
    transform: translate(40px, -30px) scale(1.1);
  }
}

.pat-canned-main {
  position: relative;
  z-index: 1;
  padding: 26px 32px 60px;
  max-width: 760px;
}

.sec-head {
  margin-bottom: 22px;
}

.sec-head h1 {
  font-weight: 600;
  font-size: 23px;
  margin: 0;
}

.sec-head .sub {
  font-size: 13px;
  color: var(--text-3);
  margin-top: 4px;
  line-height: 1.55;
}

.learn-link {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  margin-top: 8px;
  font-size: 13px;
  font-weight: 500;
  color: var(--patra-3);
  text-decoration: none;
}

.learn-link:hover {
  text-decoration: underline;
}

.learn-icon {
  width: 14px;
  height: 14px;
}

.card {
  position: relative;
  isolation: isolate;
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 16px;
  padding: 22px;
  margin-bottom: 16px;
  transition:
    transform 0.35s cubic-bezier(0.34, 1.56, 0.64, 1),
    box-shadow 0.35s,
    border-color 0.25s;
}

.card::before {
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

.card:hover::before {
  opacity: 1;
}

.card:hover {
  transform: translateY(-4px) scale(1.008);
  box-shadow:
    0 18px 40px -14px rgba(0, 0, 0, 0.55),
    0 0 26px rgba(110, 86, 207, 0.18);
  border-color: var(--patra);
}

.loading-note {
  margin: 0;
  text-align: center;
  color: var(--text-3);
  font-size: 13px;
  padding: 24px 0;
}

.card-toolbar {
  display: flex;
  align-items: center;
  justify-content: flex-end;
  gap: 12px;
  margin-bottom: 14px;
  flex-wrap: wrap;
}

.pat-search {
  flex: 1;
  min-width: 140px;
  margin-right: auto;
  background: var(--canvas);
  border: 1px solid var(--border);
  border-radius: 10px;
  padding: 8px 13px;
  color: var(--text);
  font-size: 13px;
  outline: none;
  font-family: 'Inter', sans-serif;
}

.pat-search:focus {
  border-color: var(--patra);
  box-shadow: 0 0 0 3px rgba(110, 86, 207, 0.11);
}

.sort-btn {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 34px;
  height: 34px;
  padding: 0;
  border-radius: 9px;
  border: 1px solid var(--border);
  background: var(--canvas);
  color: var(--text-3);
  cursor: pointer;
  transition: all 0.2s;
}

.sort-btn:hover {
  border-color: var(--patra);
  color: var(--patra-3);
}

.sort-icon {
  width: 18px;
  height: 18px;
}

.count-label {
  font-size: 12px;
  color: var(--text-3);
  font-family: 'JetBrains Mono', monospace;
  white-space: nowrap;
}

.btn {
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

.btn:hover {
  transform: translateY(-2px);
  box-shadow: 0 6px 16px rgba(0, 0, 0, 0.3);
  border-color: var(--patra);
}

.btn.primary {
  background: linear-gradient(135deg, var(--patra), var(--patra-deep));
  border-color: transparent;
  color: #fff;
  box-shadow: 0 4px 14px var(--patra-glow);
}

.btn.primary:hover {
  filter: brightness(1.12);
}

.btn.sm {
  padding: 7px 13px;
  font-size: 12px;
}

.cr {
  background: var(--canvas);
  border: 1px solid var(--border);
  border-radius: 13px;
  padding: 16px;
  margin-bottom: 12px;
  transition: all 0.25s;
}

.cr:last-child {
  margin-bottom: 0;
}

.cr:hover {
  border-color: var(--border-hi);
  transform: translateY(-2px);
  box-shadow: 0 10px 24px rgba(0, 0, 0, 0.3);
}

.cr-top {
  display: flex;
  align-items: center;
  gap: 9px;
  margin-bottom: 9px;
}

.cr-code {
  font-family: 'JetBrains Mono', monospace;
  font-size: 13px;
  font-weight: 600;
  color: var(--patra-3);
  background: rgba(110, 86, 207, 0.14);
  padding: 3px 10px;
  border-radius: 7px;
}

.cr-code::before {
  content: '/';
  opacity: 0.6;
}

.cr-edit {
  margin-left: auto;
  font-size: 11px;
  color: var(--text-3);
  cursor: pointer;
  background: none;
  border: none;
  padding: 4px 6px;
  font-family: 'Inter', sans-serif;
  transition: color 0.2s;
}

.cr-edit:hover {
  color: var(--patra-3);
}

.cr-delete {
  flex-shrink: 0;
}

.cr-body {
  font-size: 12.5px;
  color: var(--text-2);
  line-height: 1.55;
  max-height: 72px;
  overflow: hidden;
  position: relative;
  margin: 0;
}

.cr-body.long::after {
  content: '';
  position: absolute;
  bottom: 0;
  left: 0;
  right: 0;
  height: 24px;
  background: linear-gradient(transparent, var(--canvas));
}

.empty-card {
  text-align: center;
  padding: 36px;
  color: var(--text-4);
  font-size: 13px;
}

.empty-card .ec-ic {
  font-size: 32px;
  margin-bottom: 10px;
  opacity: 0.5;
}

.empty-action {
  margin-top: 14px;
}
</style>
