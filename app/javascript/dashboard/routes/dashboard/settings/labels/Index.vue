<script setup>
import { useAlert } from 'dashboard/composables';
import { computed, onBeforeMount, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStoreGetters, useStore } from 'dashboard/composables/store';
import { picoSearch } from '@scmmishra/pico-search';
import CustomBrandPolicyWrapper from 'dashboard/components/CustomBrandPolicyWrapper.vue';
import { getHelpUrlForFeature } from '../../../../helper/featureHelper';

import AddLabel from './AddLabel.vue';
import EditLabel from './EditLabel.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const getters = useStoreGetters();
const store = useStore();
const { t } = useI18n();

const loading = ref({});
const showAddPopup = ref(false);
const showEditPopup = ref(false);
const showDeleteConfirmationPopup = ref(false);
const selectedLabel = ref({});
const searchQuery = ref('');
const spotlight = ref(null);

const helpURL = getHelpUrlForFeature('labels');

const records = computed(() => getters['labels/getLabels'].value);

const filteredRecords = computed(() => {
  const query = searchQuery.value.trim();
  if (!query) return records.value;
  return picoSearch(records.value, query, [
    { name: 'title', weight: 4 },
    'description',
  ]);
});
const uiFlags = computed(() => getters['labels/getUIFlags'].value);

const deleteMessage = computed(() => ` ${selectedLabel.value.title}?`);

const openAddPopup = () => {
  showAddPopup.value = true;
};
const hideAddPopup = () => {
  showAddPopup.value = false;
};

const openEditPopup = response => {
  showEditPopup.value = true;
  selectedLabel.value = response;
};
const hideEditPopup = () => {
  showEditPopup.value = false;
};

const openDeletePopup = response => {
  showDeleteConfirmationPopup.value = true;
  selectedLabel.value = response;
};
const closeDeletePopup = () => {
  showDeleteConfirmationPopup.value = false;
};

const deleteLabel = async id => {
  try {
    await store.dispatch('labels/delete', id);
    useAlert(t('LABEL_MGMT.DELETE.API.SUCCESS_MESSAGE'));
  } catch (error) {
    const errorMessage =
      error?.message || t('LABEL_MGMT.DELETE.API.ERROR_MESSAGE');
    useAlert(errorMessage);
  } finally {
    loading.value[selectedLabel.value.id] = false;
  }
};

const confirmDeletion = () => {
  loading.value[selectedLabel.value.id] = true;
  closeDeletePopup();
  deleteLabel(selectedLabel.value.id);
};

onBeforeMount(() => {
  store.dispatch('labels/get');
});

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
    class="pat-list-wrap"
    @mousemove="onSpotlightMove"
    @mouseleave="onSpotlightLeave"
  >
    <div id="spotlight" ref="spotlight" />
    <div class="mesh" />

    <div class="pat-list-main" @mousemove="onCardGlow">
      <div class="sec-head">
        <h1 class="display">{{ $t('LABEL_MGMT.HEADER') }}</h1>
        <div class="sub">{{ $t('LABEL_MGMT.DESCRIPTION') }}</div>
        <CustomBrandPolicyWrapper :show-on-custom-branded-instance="false">
          <a
            v-if="helpURL"
            :href="helpURL"
            target="_blank"
            rel="noopener noreferrer"
            class="learn-link"
          >
            {{ $t('LABEL_MGMT.LEARN_MORE') }}
            <Icon icon="i-lucide-chevron-right" class="learn-icon" />
          </a>
        </CustomBrandPolicyWrapper>
      </div>

      <div v-if="uiFlags.isFetching" class="card">
        <p class="loading-note">{{ $t('LABEL_MGMT.LOADING') }}</p>
      </div>

      <div v-else-if="!records.length" class="card">
        <div class="empty-card">
          <div class="ec-ic">{{ $t('PATRA.SETTINGS.EMPTY_ICON_LABELS') }}</div>
          {{ $t('LABEL_MGMT.LIST.404') }}
          <button
            type="button"
            class="btn primary sm empty-action"
            @click="openAddPopup"
          >
            {{ $t('LABEL_MGMT.HEADER_BTN_TXT') }}
          </button>
        </div>
      </div>

      <div v-else class="card">
        <div class="card-toolbar">
          <input
            v-model="searchQuery"
            type="search"
            class="pat-search"
            :placeholder="$t('LABEL_MGMT.SEARCH_PLACEHOLDER')"
          />
          <span v-if="records.length" class="count-label">
            {{ $t('LABEL_MGMT.COUNT', { n: records.length }) }}
          </span>
          <button type="button" class="btn primary sm" @click="openAddPopup">
            {{ $t('LABEL_MGMT.HEADER_BTN_TXT') }}
          </button>
        </div>

        <div v-if="!filteredRecords.length && searchQuery" class="empty-card">
          {{ $t('LABEL_MGMT.NO_RESULTS') }}
        </div>

        <div v-for="label in filteredRecords" :key="label.title" class="lrow">
          <span class="lbl-swatch" :style="{ backgroundColor: label.color }" />
          <div class="li">
            <div class="ln">{{ label.title }}</div>
            <div v-if="label.description" class="le">
              {{ label.description }}
            </div>
          </div>
          <span class="fc">{{ label.color }}</span>
          <div class="row-actions">
            <Button
              v-tooltip.top="$t('LABEL_MGMT.FORM.EDIT')"
              icon="i-woot-edit-pen"
              slate
              sm
              :is-loading="loading[label.id]"
              @click="openEditPopup(label)"
            />
            <Button
              v-tooltip.top="$t('LABEL_MGMT.FORM.DELETE')"
              icon="i-woot-bin"
              slate
              sm
              class="hover:enabled:text-n-ruby-11 hover:enabled:bg-n-ruby-2"
              :is-loading="loading[label.id]"
              @click="openDeletePopup(label)"
            />
          </div>
        </div>
      </div>
    </div>

    <woot-modal v-model:show="showAddPopup" :on-close="hideAddPopup">
      <AddLabel @close="hideAddPopup" />
    </woot-modal>

    <woot-modal v-model:show="showEditPopup" :on-close="hideEditPopup">
      <EditLabel :selected-response="selectedLabel" @close="hideEditPopup" />
    </woot-modal>

    <woot-delete-modal
      v-model:show="showDeleteConfirmationPopup"
      :on-close="closeDeletePopup"
      :on-confirm="confirmDeletion"
      :title="$t('LABEL_MGMT.DELETE.CONFIRM.TITLE')"
      :message="$t('LABEL_MGMT.DELETE.CONFIRM.MESSAGE')"
      :message-value="deleteMessage"
      :confirm-text="$t('LABEL_MGMT.DELETE.CONFIRM.YES')"
      :reject-text="$t('LABEL_MGMT.DELETE.CONFIRM.NO')"
    />
  </div>
</template>

<style scoped>
.pat-list-wrap {
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

.pat-list-main {
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
  margin-bottom: 6px;
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

.lrow {
  display: flex;
  align-items: center;
  gap: 13px;
  padding: 14px 0;
  border-bottom: 1px solid var(--border);
  transition: all 0.22s cubic-bezier(0.34, 1.56, 0.64, 1);
  border-radius: 10px;
}

.lrow:last-child {
  border-bottom: none;
}

.lrow:hover {
  background: var(--surface-2);
  transform: translateX(3px);
  padding-left: 8px;
}

.lbl-swatch {
  width: 14px;
  height: 14px;
  border-radius: 4px;
  flex-shrink: 0;
  border: 1px solid var(--border-hi);
}

.li {
  flex: 1;
  min-width: 0;
}

.ln {
  font-size: 13.5px;
  font-weight: 500;
}

.le {
  font-size: 11.5px;
  color: var(--text-3);
  font-family: 'JetBrains Mono', monospace;
}

.fc {
  font-family: 'JetBrains Mono', monospace;
  font-size: 12px;
  color: var(--text-3);
  flex-shrink: 0;
}

.row-actions {
  display: flex;
  gap: 8px;
  flex-shrink: 0;
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
