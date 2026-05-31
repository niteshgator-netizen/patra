<script setup>
import { useAlert } from 'dashboard/composables';
import { computed, onMounted, ref } from 'vue';
import Avatar from 'next/avatar/Avatar.vue';
import { useI18n } from 'vue-i18n';
import { picoSearch } from '@scmmishra/pico-search';
import {
  useStoreGetters,
  useStore,
  useMapGetter,
} from 'dashboard/composables/store';
import CustomBrandPolicyWrapper from 'dashboard/components/CustomBrandPolicyWrapper.vue';
import { getHelpUrlForFeature } from '../../../../helper/featureHelper';
import Icon from 'dashboard/components-next/icon/Icon.vue';

import AddAgent from './AddAgent.vue';
import EditAgent from './EditAgent.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const getters = useStoreGetters();
const store = useStore();
const { t } = useI18n();

const loading = ref({});
const showAddPopup = ref(false);
const showDeletePopup = ref(false);
const showEditPopup = ref(false);
const agentAPI = ref({ message: '' });
const currentAgent = ref({});
const searchQuery = ref('');
const spotlight = ref(null);

const helpURL = getHelpUrlForFeature('agents');

const deleteConfirmText = computed(
  () => `${t('AGENT_MGMT.DELETE.CONFIRM.YES')} ${currentAgent.value.name}`
);
const deleteRejectText = computed(() => {
  return `${t('AGENT_MGMT.DELETE.CONFIRM.NO')} ${currentAgent.value.name}`;
});
const deleteMessage = computed(() => {
  return ` ${currentAgent.value.name}?`;
});

const agentList = computed(() => getters['agents/getAgents'].value);

const filteredAgentList = computed(() => {
  const query = searchQuery.value.trim();
  if (!query) return agentList.value;
  return picoSearch(agentList.value, query, ['name', 'email']);
});

const uiFlags = computed(() => getters['agents/getUIFlags'].value);
const currentUserId = computed(() => getters.getCurrentUserID.value);
const customRoles = useMapGetter('customRole/getCustomRoles');

onMounted(() => {
  store.dispatch('agents/get');
  store.dispatch('customRole/getCustomRole');
});

const findCustomRole = agent =>
  customRoles.value.find(role => role.id === agent.custom_role_id);

const getAgentRoleName = agent => {
  if (!agent.custom_role_id) {
    return t(`AGENT_MGMT.AGENT_TYPES.${agent.role.toUpperCase()}`);
  }
  const customRole = findCustomRole(agent);
  return customRole ? customRole.name : '';
};

const getAgentRolePermissions = agent => {
  if (!agent.custom_role_id) {
    return [];
  }
  const customRole = findCustomRole(agent);
  return customRole?.permissions || [];
};

const getRoleClass = agent => {
  if (agent.custom_role_id) return 'role custom';
  return agent.role === 'administrator' ? 'role admin' : 'role agent';
};

const verifiedAdministrators = computed(() => {
  return agentList.value.filter(
    agent => agent.role === 'administrator' && agent.confirmed
  );
});

const showEditAction = agent => {
  return currentUserId.value !== agent.id;
};

const showDeleteAction = agent => {
  if (currentUserId.value === agent.id) {
    return false;
  }

  if (!agent.confirmed) {
    return true;
  }

  if (agent.role === 'administrator') {
    return verifiedAdministrators.value.length !== 1;
  }
  return true;
};

const showAlertMessage = message => {
  loading.value[currentAgent.value.id] = false;
  currentAgent.value = {};
  agentAPI.value.message = message;
  useAlert(message);
};

const openAddPopup = () => {
  showAddPopup.value = true;
};
const hideAddPopup = () => {
  showAddPopup.value = false;
};

const openEditPopup = agent => {
  showEditPopup.value = true;
  currentAgent.value = agent;
};
const hideEditPopup = () => {
  showEditPopup.value = false;
};

const openDeletePopup = agent => {
  showDeletePopup.value = true;
  currentAgent.value = agent;
};
const closeDeletePopup = () => {
  showDeletePopup.value = false;
};

const deleteAgent = async id => {
  try {
    await store.dispatch('agents/delete', id);
    showAlertMessage(t('AGENT_MGMT.DELETE.API.SUCCESS_MESSAGE'));
  } catch (error) {
    showAlertMessage(t('AGENT_MGMT.DELETE.API.ERROR_MESSAGE'));
  }
};
const confirmDeletion = () => {
  loading.value[currentAgent.value.id] = true;
  closeDeletePopup();
  deleteAgent(currentAgent.value.id);
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
        <h1 class="display">{{ $t('AGENT_MGMT.HEADER') }}</h1>
        <div class="sub">{{ $t('AGENT_MGMT.DESCRIPTION') }}</div>
        <CustomBrandPolicyWrapper :show-on-custom-branded-instance="false">
          <a
            v-if="helpURL"
            :href="helpURL"
            target="_blank"
            rel="noopener noreferrer"
            class="learn-link"
          >
            {{ $t('AGENT_MGMT.LEARN_MORE') }}
            <Icon icon="i-lucide-chevron-right" class="learn-icon" />
          </a>
        </CustomBrandPolicyWrapper>
      </div>

      <div v-if="uiFlags.isFetching" class="card">
        <p class="loading-note">{{ $t('AGENT_MGMT.LOADING') }}</p>
      </div>

      <div v-else-if="!agentList.length" class="card">
        <div class="empty-card">
          <div class="ec-ic">{{ $t('PATRA.SETTINGS.EMPTY_ICON_AGENTS') }}</div>
          {{ $t('AGENT_MGMT.LIST.404') }}
          <button
            type="button"
            class="btn primary sm empty-action"
            @click="openAddPopup"
          >
            {{ $t('AGENT_MGMT.HEADER_BTN_TXT') }}
          </button>
        </div>
      </div>

      <div v-else class="card">
        <div class="card-toolbar">
          <input
            v-model="searchQuery"
            type="search"
            class="pat-search"
            :placeholder="$t('AGENT_MGMT.SEARCH_PLACEHOLDER')"
          />
          <span v-if="agentList.length" class="count-label">
            {{ $t('AGENT_MGMT.COUNT', { n: agentList.length }) }}
          </span>
          <button type="button" class="btn primary sm" @click="openAddPopup">
            {{ $t('AGENT_MGMT.HEADER_BTN_TXT') }}
          </button>
        </div>

        <div v-if="!filteredAgentList.length && searchQuery" class="empty-card">
          {{ $t('AGENT_MGMT.NO_RESULTS') }}
        </div>

        <div v-for="agent in filteredAgentList" :key="agent.email" class="lrow">
          <div class="la la-wrap">
            <Avatar
              :src="agent.thumbnail"
              :name="agent.name"
              :status="agent.availability_status"
              :size="38"
              hide-offline-status
            />
          </div>
          <div class="li">
            <div class="ln">{{ agent.name }}</div>
            <div class="le">{{ agent.email }}</div>
          </div>
          <span
            class="relative"
            :class="{
              'group cursor-pointer': agent.custom_role_id,
            }"
          >
            <span :class="getRoleClass(agent)">{{
              getAgentRoleName(agent)
            }}</span>
            <div v-if="agent.custom_role_id" class="role-tooltip">
              <span class="role-tooltip-title">
                {{ $t('AGENT_MGMT.LIST.AVAILABLE_CUSTOM_ROLE') }}
              </span>
              <ul class="role-tooltip-list">
                <li
                  v-for="permission in getAgentRolePermissions(agent)"
                  :key="permission"
                >
                  {{
                    $t(`CUSTOM_ROLE.PERMISSIONS.${permission.toUpperCase()}`)
                  }}
                </li>
              </ul>
            </div>
          </span>
          <span v-if="agent.confirmed" class="verified">
            {{ $t('AGENT_MGMT.LIST.VERIFIED') }}
          </span>
          <span v-else class="verified pending">
            {{ $t('AGENT_MGMT.LIST.VERIFICATION_PENDING') }}
          </span>
          <div class="row-actions">
            <Button
              v-if="showEditAction(agent)"
              v-tooltip.top="$t('AGENT_MGMT.EDIT.BUTTON_TEXT')"
              icon="i-woot-edit-pen"
              slate
              sm
              @click="openEditPopup(agent)"
            />
            <Button
              v-if="showDeleteAction(agent)"
              v-tooltip.top="$t('AGENT_MGMT.DELETE.BUTTON_TEXT')"
              icon="i-woot-bin"
              slate
              sm
              class="hover:enabled:text-n-ruby-11 hover:enabled:bg-n-ruby-2"
              :is-loading="loading[agent.id]"
              @click="openDeletePopup(agent)"
            />
          </div>
        </div>
      </div>
    </div>

    <woot-modal v-model:show="showAddPopup" :on-close="hideAddPopup">
      <AddAgent @close="hideAddPopup" />
    </woot-modal>

    <woot-modal v-model:show="showEditPopup" :on-close="hideEditPopup">
      <EditAgent
        v-if="showEditPopup"
        :id="currentAgent.id"
        :name="currentAgent.name"
        :provider="currentAgent.provider"
        :type="currentAgent.role"
        :email="currentAgent.email"
        :availability="currentAgent.availability_status"
        :custom-role-id="currentAgent.custom_role_id"
        @close="hideEditPopup"
      />
    </woot-modal>

    <woot-delete-modal
      v-model:show="showDeletePopup"
      :on-close="closeDeletePopup"
      :on-confirm="confirmDeletion"
      :title="$t('AGENT_MGMT.DELETE.CONFIRM.TITLE')"
      :message="$t('AGENT_MGMT.DELETE.CONFIRM.MESSAGE')"
      :message-value="deleteMessage"
      :confirm-text="deleteConfirmText"
      :reject-text="deleteRejectText"
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
  --green: #3fb950;
  --blue: #58a6ff;
  --red: #f85149;
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

.la {
  width: 38px;
  height: 38px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  color: #fff;
  font-weight: 600;
  font-size: 13px;
  flex-shrink: 0;
  overflow: hidden;
}

.la-wrap {
  background: linear-gradient(135deg, var(--patra), var(--patra-2));
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

.role {
  font-size: 11px;
  font-weight: 600;
  padding: 3px 10px;
  border-radius: 20px;
  white-space: nowrap;
}

.role.admin,
.role.custom {
  background: rgba(110, 86, 207, 0.16);
  color: var(--patra-3);
}

.role.agent {
  background: rgba(88, 166, 255, 0.16);
  color: var(--blue);
}

.verified {
  font-size: 10px;
  color: var(--green);
  font-family: 'JetBrains Mono', monospace;
  white-space: nowrap;
}

.verified.pending {
  color: var(--text-3);
}

.role-tooltip {
  position: absolute;
  left: 0;
  z-index: 10;
  display: none;
  width: 300px;
  background: var(--surface-3);
  border: 1px solid var(--border-hi);
  border-radius: 12px;
  box-shadow: 0 24px 60px -20px rgba(0, 0, 0, 0.8);
  padding: 16px;
  top: calc(100% + 8px);
}

.group:hover .role-tooltip {
  display: block;
}

.role-tooltip-title {
  display: block;
  font-size: 14px;
  font-weight: 600;
  margin-bottom: 8px;
}

.role-tooltip-list {
  margin: 0;
  padding-left: 18px;
  font-size: 13px;
  color: var(--text-2);
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
