<script setup>
/* global axios */
// ADM4 DEFERRED-FRONTEND: SPA-side impersonation banner.
// Contract (PATRA_FEAT_LOG.md): while a super-admin impersonation marker is
// active, every console response carries X-Patra-Impersonation, and
// GET /super_admin/patra_impersonation returns
//   { active, impersonator_id, target_user_id, started_at, expires_at }.
// The SPA can't see console response headers, so it polls the JSON endpoint —
// it answers from the same super-admin session cookie the operator's browser
// carries during impersonation. For a normal agent the devise gate redirects
// to the console sign-in HTML, which fails the object/active check → hidden.
import { ref, computed, onMounted, onUnmounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';

const { t } = useI18n();

const POLL_MS = 60_000;

const status = ref(null);
const exiting = ref(false);
let pollTimer = null;

const accountId = useMapGetter('getCurrentAccountId');
const getAccount = useMapGetter('accounts/getAccount');

const active = computed(() => status.value?.active === true);

const accountName = computed(() => {
  const account = getAccount.value?.(accountId.value);
  return account?.name || '';
});

const expiresLabel = computed(() => {
  const iso = status.value?.expires_at;
  if (!iso) return '';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '';
  return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
});

const fetchStatus = async () => {
  try {
    const { data } = await axios.get('/super_admin/patra_impersonation', {
      headers: { Accept: 'application/json' },
    });
    // Non-super-admin sessions get redirected to the sign-in HTML page —
    // only trust a real JSON object with active === true.
    status.value =
      data && typeof data === 'object' && data.active === true ? data : null;
  } catch (e) {
    status.value = null;
  }
};

const exitImpersonation = async () => {
  if (exiting.value) return;
  exiting.value = true;
  try {
    const csrf = document.querySelector('meta[name="csrf-token"]')?.content;
    await axios.delete('/super_admin/patra_impersonation', {
      headers: csrf ? { 'X-CSRF-Token': csrf } : {},
    });
  } catch (e) {
    // exit redirects to the console root (HTML) — axios may "fail" on it;
    // the re-fetch below is the source of truth either way.
  } finally {
    await fetchStatus();
    exiting.value = false;
  }
};

onMounted(() => {
  fetchStatus();
  pollTimer = setInterval(fetchStatus, POLL_MS);
});

onUnmounted(() => {
  if (pollTimer) clearInterval(pollTimer);
});
</script>

<template>
  <div v-if="active" class="patra-impersonation-banner" role="alert">
    <span class="pib-dot" aria-hidden="true" />
    <span class="pib-text">
      {{
        t('PATRA.IMPERSONATION.BANNER', {
          account: accountName || `#${accountId}`,
          userId: status.target_user_id,
        })
      }}
      <template v-if="expiresLabel">
        · {{ t('PATRA.IMPERSONATION.EXPIRES', { time: expiresLabel }) }}
      </template>
    </span>
    <button
      type="button"
      class="pib-exit"
      :disabled="exiting"
      @click="exitImpersonation"
    >
      {{
        exiting
          ? t('PATRA.IMPERSONATION.EXITING')
          : t('PATRA.IMPERSONATION.EXIT')
      }}
    </button>
  </div>
</template>

<style scoped>
.patra-impersonation-banner {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 10px;
  padding: 6px 16px;
  font-size: 12.5px;
  font-weight: 500;
  color: #fff;
  background: linear-gradient(90deg, #b91c1c, #dc2626);
  border-bottom: 1px solid rgba(0, 0, 0, 0.25);
  flex-shrink: 0;
}

.pib-dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: #fff;
  flex-shrink: 0;
  animation: pib-pulse 1.6s ease-in-out infinite;
}

.pib-text {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.pib-exit {
  flex-shrink: 0;
  font-size: 12px;
  font-weight: 700;
  padding: 3px 12px;
  border-radius: 6px;
  border: 1px solid rgba(255, 255, 255, 0.6);
  background: rgba(255, 255, 255, 0.12);
  color: #fff;
  cursor: pointer;
  transition: background 0.2s;
}

.pib-exit:hover:not(:disabled) {
  background: rgba(255, 255, 255, 0.24);
}

.pib-exit:disabled {
  opacity: 0.6;
  cursor: wait;
}

@keyframes pib-pulse {
  0%,
  100% {
    opacity: 1;
  }
  50% {
    opacity: 0.35;
  }
}
</style>
