<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { picoSearch } from '@scmmishra/pico-search';
import Avatar from 'next/avatar/Avatar.vue';
import { useAdmin } from 'dashboard/composables/useAdmin';
import CustomBrandPolicyWrapper from 'dashboard/components/CustomBrandPolicyWrapper.vue';
import { getHelpUrlForFeature } from '../../../../helper/featureHelper';
import {
  useMapGetter,
  useStoreGetters,
  useStore,
} from 'dashboard/composables/store';
import ChannelName from './components/ChannelName.vue';
import ChannelIcon from 'next/icon/ChannelIcon.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const getters = useStoreGetters();
const store = useStore();
const { t } = useI18n();
const { isAdmin } = useAdmin();

const showDeletePopup = ref(false);
const selectedInbox = ref({});
const searchQuery = ref('');
const spotlight = ref(null);

const helpURL = getHelpUrlForFeature('inboxes');

const inboxes = useMapGetter('inboxes/getInboxes');

const inboxesList = computed(() => {
  return inboxes.value?.slice().sort((a, b) => a.name.localeCompare(b.name));
});

const filteredInboxesList = computed(() => {
  const query = searchQuery.value.trim();
  if (!query) return inboxesList.value;
  return picoSearch(inboxesList.value, query, ['name', 'channel_type']);
});

const uiFlags = computed(() => getters['inboxes/getUIFlags'].value);

const deleteConfirmText = computed(
  () => `${t('INBOX_MGMT.DELETE.CONFIRM.YES')} ${selectedInbox.value.name}`
);

const deleteRejectText = computed(
  () => `${t('INBOX_MGMT.DELETE.CONFIRM.NO')} ${selectedInbox.value.name}`
);

const confirmDeleteMessage = computed(
  () => `${t('INBOX_MGMT.DELETE.CONFIRM.MESSAGE')} ${selectedInbox.value.name}?`
);
const confirmPlaceHolderText = computed(
  () =>
    `${t('INBOX_MGMT.DELETE.CONFIRM.PLACE_HOLDER', {
      inboxName: selectedInbox.value.name,
    })}`
);

const deleteInbox = async ({ id }) => {
  try {
    await store.dispatch('inboxes/delete', id);
    useAlert(t('INBOX_MGMT.DELETE.API.SUCCESS_MESSAGE'));
  } catch (error) {
    useAlert(t('INBOX_MGMT.DELETE.API.ERROR_MESSAGE'));
  }
};
const closeDelete = () => {
  showDeletePopup.value = false;
  selectedInbox.value = {};
};

const confirmDeletion = () => {
  deleteInbox(selectedInbox.value);
  closeDelete();
};
const openDelete = inbox => {
  showDeletePopup.value = true;
  selectedInbox.value = inbox;
};

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
        <h1 class="display">{{ $t('INBOX_MGMT.HEADER') }}</h1>
        <div class="sub">{{ $t('INBOX_MGMT.DESCRIPTION') }}</div>
        <CustomBrandPolicyWrapper :show-on-custom-branded-instance="false">
          <a
            v-if="helpURL"
            :href="helpURL"
            target="_blank"
            rel="noopener noreferrer"
            class="learn-link"
          >
            {{ $t('INBOX_MGMT.LEARN_MORE') }}
            <Icon icon="i-lucide-chevron-right" class="learn-icon" />
          </a>
        </CustomBrandPolicyWrapper>
      </div>

      <div v-if="uiFlags.isFetching" class="card">
        <p class="loading-note">{{ $t('PATRA.SETTINGS.LOADING') }}</p>
      </div>

      <div v-else-if="!inboxesList.length" class="card">
        <div class="empty-card">
          <div class="ec-ic">{{ $t('PATRA.SETTINGS.EMPTY_ICON_INBOXES') }}</div>
          {{ $t('INBOX_MGMT.LIST.404') }}
          <router-link
            v-if="isAdmin"
            :to="{ name: 'settings_inbox_new' }"
            class="empty-action-link"
          >
            <button type="button" class="btn primary sm">
              {{ $t('SETTINGS.INBOXES.NEW_INBOX') }}
            </button>
          </router-link>
        </div>
      </div>

      <div v-else class="card">
        <div class="card-toolbar">
          <input
            v-model="searchQuery"
            type="search"
            class="pat-search"
            :placeholder="$t('INBOX_MGMT.SEARCH_PLACEHOLDER')"
          />
          <span v-if="inboxesList.length" class="count-label">
            {{ $t('INBOX_MGMT.COUNT', { n: inboxesList.length }) }}
          </span>
          <router-link v-if="isAdmin" :to="{ name: 'settings_inbox_new' }">
            <button type="button" class="btn primary sm">
              {{ $t('SETTINGS.INBOXES.NEW_INBOX') }}
            </button>
          </router-link>
        </div>

        <div
          v-if="!filteredInboxesList.length && searchQuery"
          class="empty-card"
        >
          {{ $t('INBOX_MGMT.NO_RESULTS') }}
        </div>

        <div v-for="inbox in filteredInboxesList" :key="inbox.id" class="lrow">
          <div v-if="inbox.avatar_url" class="chan-ic chan-ic-avatar">
            <Avatar
              :src="inbox.avatar_url"
              :name="inbox.name"
              :size="24"
              rounded-full
            />
          </div>
          <div v-else class="chan-ic">
            <ChannelIcon class="chan-icon-svg" :inbox="inbox" />
          </div>
          <div class="li">
            <div class="ln">{{ inbox.name }}</div>
            <ChannelName
              :channel-type="inbox.channel_type"
              :medium="inbox.medium"
              :voice-enabled="inbox.voice_enabled"
              :additional-attributes="inbox.additional_attributes"
              class="le"
            />
          </div>
          <div class="row-actions">
            <router-link
              :to="{
                name: 'settings_inbox_show',
                params: { inboxId: inbox.id },
              }"
            >
              <Button
                v-if="isAdmin"
                v-tooltip.top="$t('INBOX_MGMT.SETTINGS')"
                icon="i-woot-settings"
                slate
                sm
              />
            </router-link>
            <Button
              v-if="isAdmin"
              v-tooltip.top="$t('INBOX_MGMT.DELETE.BUTTON_TEXT')"
              icon="i-woot-bin"
              slate
              sm
              class="hover:enabled:text-n-ruby-11 hover:enabled:bg-n-ruby-2"
              @click="openDelete(inbox)"
            />
          </div>
        </div>
      </div>
    </div>

    <woot-confirm-delete-modal
      v-if="showDeletePopup"
      v-model:show="showDeletePopup"
      :title="$t('INBOX_MGMT.DELETE.CONFIRM.TITLE')"
      :message="confirmDeleteMessage"
      :confirm-text="deleteConfirmText"
      :reject-text="deleteRejectText"
      :confirm-value="selectedInbox.name"
      :confirm-place-holder-text="confirmPlaceHolderText"
      @on-confirm="confirmDeletion"
      @on-close="closeDelete"
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

.chan-ic {
  width: 36px;
  height: 36px;
  border-radius: 9px;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
  background: var(--surface-3);
  border: 1px solid var(--border-hi);
}

.chan-ic-avatar {
  background: var(--surface-2);
}

.chan-icon-svg {
  width: 18px;
  height: 18px;
  color: var(--text-2);
}

.li {
  flex: 1;
  min-width: 0;
}

.ln {
  font-size: 13.5px;
  font-weight: 500;
  text-transform: capitalize;
}

.le {
  font-size: 11.5px;
  color: var(--text-3);
  font-family: 'JetBrains Mono', monospace;
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

.empty-action-link {
  display: inline-block;
  margin-top: 14px;
  text-decoration: none;
}
</style>
