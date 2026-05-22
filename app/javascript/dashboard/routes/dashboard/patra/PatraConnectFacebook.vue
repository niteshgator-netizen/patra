<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { frontendURL } from 'dashboard/helper/URLHelper';
import Button from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useStore();

const accountId = computed(() => Number(route.params.accountId));

const config = typeof window !== 'undefined' ? window.chatwootConfig || {} : {};
const fbAppId = config.fbAppId || '';
const fbApiVersion = (config.fbApiVersion || 'v18.0').replace(/^v/, '');

const isBusy = ref(false);
const isSubmittingPages = ref(false);
const pages = ref([]);
const userAccessToken = ref('');
const facebookIdentityId = ref(null);
const fbUserName = ref('');
const alreadyConnectedIds = ref([]);
const alreadyConnectedPages = ref([]);
const selectedIds = ref(new Set());
const errorMessage = ref('');
const byocReady = ref(false);
const byocAppId = ref('');
const isByocOAuthStarting = ref(false);

const redirectUri = computed(() => {
  const base = (config.hostURL || 'https://patrahq.com').replace(/\/$/, '');
  return `${base}/patra/oauth/callback`;
});

const businessManagerLink = computed(
  () => 'https://business.facebook.com/settings/apps'
);

const apiBase = () => `/api/v1/accounts/${accountId.value}/patra`;

const isPageConnected = pageId =>
  alreadyConnectedIds.value.includes(String(pageId));

const isPageLegacyConnected = pageId =>
  alreadyConnectedPages.value.some(
    p => String(p.fb_page_id) === String(pageId) && p.legacy
  );

const selectablePages = computed(() =>
  pages.value.filter(p => !isPageConnected(p.id))
);

const allSelected = computed(
  () =>
    selectablePages.value.length > 0 &&
    selectablePages.value.every(p => selectedIds.value.has(p.id))
);

const selectedCount = computed(() => selectedIds.value.size);

const toggleSelectAll = () => {
  if (allSelected.value) {
    selectedIds.value = new Set();
  } else {
    selectedIds.value = new Set(selectablePages.value.map(p => p.id));
  }
};

const togglePage = id => {
  if (isPageConnected(id)) return;
  const next = new Set(selectedIds.value);
  if (next.has(id)) {
    next.delete(id);
  } else {
    next.add(id);
  }
  selectedIds.value = next;
};

const isPageSelected = id => selectedIds.value.has(id);

function loadFacebookSdk() {
  return new Promise((resolve, reject) => {
    if (window.FB) {
      resolve();
      return;
    }
    window.fbAsyncInit = () => {
      window.FB.init({
        appId: fbAppId,
        cookie: true,
        xfbml: false,
        version: `v${fbApiVersion}`,
      });
      resolve();
    };
    const script = document.createElement('script');
    script.async = true;
    script.defer = true;
    script.crossOrigin = 'anonymous';
    script.src = 'https://connect.facebook.net/en_US/sdk.js';
    script.onerror = () => reject(new Error('Facebook SDK failed to load'));
    document.body.appendChild(script);
  });
}

function fbLogin() {
  return new Promise(resolve => {
    window.FB.login(resolve, {
      scope:
        'pages_messaging,pages_show_list,pages_manage_metadata,business_management',
    });
  });
}

const connectFacebook = async () => {
  errorMessage.value = '';
  if (!fbAppId) {
    errorMessage.value = t('PATRA_CONNECT_FACEBOOK.ERRORS.MISSING_APP_ID');
    return;
  }
  isBusy.value = true;
  try {
    await loadFacebookSdk();
    const response = await fbLogin();
    const token = response?.authResponse?.accessToken;
    if (response?.status !== 'connected' || !token) {
      errorMessage.value = t('PATRA_CONNECT_FACEBOOK.ERRORS.LOGIN_CANCELLED');
      return;
    }
    const { data } = await window.axios.post(`${apiBase()}/fb_connect`, {
      access_token: token,
    });
    pages.value = Array.isArray(data?.pages) ? data.pages : [];
    userAccessToken.value = data.user_access_token || '';
    facebookIdentityId.value = data.facebook_identity_id || null;
    fbUserName.value = data.fb_user_name || '';
    alreadyConnectedPages.value = Array.isArray(data?.already_connected_pages)
      ? data.already_connected_pages
      : [];
    alreadyConnectedIds.value = Array.isArray(data?.already_connected_fb_page_ids)
      ? data.already_connected_fb_page_ids.map(String)
      : alreadyConnectedPages.value.map(p => String(p.fb_page_id));
    selectedIds.value = new Set(
      selectablePages.value.map(p => p.id)
    );
  } catch (e) {
    const msg = e.response?.data?.error || e.message;
    errorMessage.value = msg || t('PATRA_CONNECT_FACEBOOK.ERRORS.GENERIC');
  } finally {
    isBusy.value = false;
  }
};

const connectSelectedPages = async () => {
  errorMessage.value = '';
  const selected = pages.value.filter(
    p => selectedIds.value.has(p.id) && !isPageConnected(p.id)
  );
  if (selected.length === 0) {
    useAlert(t('PATRA_CONNECT_FACEBOOK.ERRORS.SELECT_ONE'));
    return;
  }
  isSubmittingPages.value = true;
  try {
    const { data } = await window.axios.post(`${apiBase()}/fb_connect_pages`, {
      user_access_token: userAccessToken.value,
      facebook_identity_id: facebookIdentityId.value,
      pages: selected.map(p => ({
        id: p.id,
        name: p.name,
        access_token: p.access_token,
      })),
    });
    const results = Array.isArray(data?.pages) ? data.pages : [];
    const created = results.filter(r => r.action === 'created').length;
    const updated = results.filter(r => r.action === 'updated').length;
    await store.dispatch('inboxes/get');
    const summary =
      created > 0 || updated > 0
        ? `Connected ${created} new page(s), refreshed ${updated} existing.`
        : t('PATRA_CONNECT_FACEBOOK.SUCCESS');
    useAlert(summary);
    router.push(frontendURL(`accounts/${accountId.value}/settings/inboxes/list`));
  } catch (e) {
    const msg = e.response?.data?.error || e.message;
    errorMessage.value = msg || t('PATRA_CONNECT_FACEBOOK.ERRORS.GENERIC');
  } finally {
    isSubmittingPages.value = false;
  }
};

const fetchByocStatus = async () => {
  try {
    const { data } = await window.axios.get(`${apiBase()}/meta_app`);
    byocReady.value = !!data?.has_byoc_app;
    byocAppId.value = data?.app_id || '';
  } catch {
    byocReady.value = false;
    byocAppId.value = '';
  }
};

const startByocOAuth = async () => {
  errorMessage.value = '';
  isByocOAuthStarting.value = true;
  try {
    const { data } = await window.axios.post(`${apiBase()}/byoc_oauth_url`);
    if (data?.url) {
      window.location.href = data.url;
      return;
    }
    errorMessage.value = 'Could not start OAuth. Try again.';
  } catch (e) {
    const msg = e.response?.data?.error || e.message;
    errorMessage.value = msg || 'Could not start OAuth.';
  } finally {
    isByocOAuthStarting.value = false;
  }
};

onMounted(() => {
  store.dispatch('inboxes/get');
  fetchByocStatus();
});
</script>

<template>
  <div class="flex flex-col max-w-3xl mx-auto p-6 gap-6">
    <div>
      <h1 class="text-xl font-semibold text-n-slate-12">
        {{ t('PATRA_CONNECT_FACEBOOK.TITLE') }}
      </h1>
      <p class="text-sm text-n-slate-11 mt-1">
        {{ t('PATRA_CONNECT_FACEBOOK.SUBTITLE') }}
      </p>
    </div>

    <div
      v-if="errorMessage"
      class="text-sm text-n-ruby-11 bg-n-ruby-3/30 rounded-lg px-3 py-2"
    >
      {{ errorMessage }}
    </div>

    <section
      v-if="byocReady"
      class="flex flex-col gap-3 p-4 rounded-xl border border-n-weak bg-n-alpha-2"
    >
      <h3 class="text-base font-semibold text-n-slate-12">
        {{ t('PATRA_CONNECT_FACEBOOK.BYOC.USING_OWN_APP') }}
      </h3>
      <p class="text-sm text-n-slate-11">
        {{ t('PATRA_CONNECT_FACEBOOK.BYOC.APP_ID', { id: byocAppId }) }}
      </p>
      <p class="text-sm text-n-slate-11">
        {{ t('PATRA_CONNECT_FACEBOOK.BYOC.REDIRECT_URI_HELP') }}
      </p>
      <code
        class="text-xs font-mono break-all text-n-slate-12 bg-n-solid-3 rounded-lg px-3 py-2"
      >
        {{ redirectUri }}
      </code>

      <div
        class="flex flex-col gap-2 p-4 rounded-lg border border-n-weak bg-n-solid-2"
      >
        <h4 class="text-sm font-semibold text-n-slate-12">
          {{ t('PATRA_CONNECT_FACEBOOK.BYOC.BM_NOTICE_TITLE') }}
        </h4>
        <p class="text-sm text-n-slate-11 whitespace-pre-line">
          {{ t('PATRA_CONNECT_FACEBOOK.BYOC.BM_NOTICE_BODY') }}
        </p>
        <a
          :href="businessManagerLink"
          target="_blank"
          rel="noopener noreferrer"
          class="inline-flex self-start text-sm font-medium text-violet-600 hover:text-violet-700 underline-offset-2 hover:underline"
        >
          {{ t('PATRA_CONNECT_FACEBOOK.BYOC.BM_NOTICE_LINK') }}
        </a>
        <p class="text-xs text-n-slate-10">
          {{ t('PATRA_CONNECT_FACEBOOK.BYOC.BM_NOTICE_FOOTNOTE') }}
        </p>
      </div>

      <Button
        :label="t('PATRA_CONNECT_FACEBOOK.BYOC.CONNECT_BUTTON')"
        class="!bg-violet-600 hover:!bg-violet-700 !text-white self-start min-h-11"
        :is-loading="isByocOAuthStarting"
        @click="startByocOAuth"
      />
    </section>

    <div v-if="pages.length === 0" class="flex flex-col items-start gap-4">
      <Button
        :label="t('PATRA_CONNECT_FACEBOOK.CONNECT_BUTTON')"
        class="!bg-violet-600 hover:!bg-violet-700 !text-white !border-violet-600 min-h-12 px-8 text-base font-medium"
        :is-loading="isBusy"
        @click="connectFacebook"
      />
    </div>

    <div v-else class="flex flex-col gap-4">
      <p
        v-if="fbUserName"
        class="text-sm text-n-slate-11"
      >
        {{ t('PATRA_CONNECT_FACEBOOK.CONNECTED_AS', { name: fbUserName }) }}
      </p>
      <label
        class="flex items-center gap-2 text-sm font-medium text-n-slate-12 cursor-pointer"
      >
        <input
          type="checkbox"
          class="rounded border-n-weak text-violet-600 focus:ring-violet-500"
          :checked="allSelected"
          :disabled="selectablePages.length === 0"
          @change="toggleSelectAll"
        />
        {{ t('PATRA_CONNECT_FACEBOOK.SELECT_ALL') }}
      </label>

      <div
        class="grid grid-cols-1 sm:grid-cols-2 gap-3 max-h-[480px] overflow-y-auto"
      >
        <label
          v-for="page in pages"
          :key="page.id"
          class="flex gap-3 items-center p-3 rounded-xl border border-n-weak bg-n-alpha-2"
          :class="
            isPageConnected(page.id)
              ? 'opacity-75 cursor-not-allowed'
              : 'cursor-pointer hover:bg-n-alpha-1'
          "
        >
          <input
            type="checkbox"
            class="rounded border-n-weak text-violet-600 focus:ring-violet-500 shrink-0"
            :checked="isPageSelected(page.id)"
            :disabled="isPageConnected(page.id)"
            @change="togglePage(page.id)"
          />
          <img
            v-if="page.picture"
            :src="page.picture"
            :alt="page.name"
            class="size-12 rounded-full object-cover shrink-0 bg-n-slate-4"
          />
          <div class="min-w-0 flex-1">
            <div class="flex items-center gap-2 min-w-0">
              <div class="text-sm font-medium text-n-slate-12 truncate">
                {{ page.name }}
              </div>
              <span
                v-if="isPageConnected(page.id) && isPageLegacyConnected(page.id)"
                class="shrink-0 text-xs font-medium text-n-amber-11 bg-n-amber-3/50 rounded-full px-2 py-0.5"
              >
                Already connected (legacy) ⚠️
              </span>
              <span
                v-else-if="isPageConnected(page.id)"
                class="shrink-0 text-xs font-medium text-n-teal-11 bg-n-teal-3/40 rounded-full px-2 py-0.5"
              >
                Already connected ✓
              </span>
            </div>
            <div
              v-if="page.category"
              class="text-xs text-n-slate-10 truncate"
            >
              {{ page.category }}
            </div>
          </div>
        </label>
      </div>

      <Button
        :label="
          t('PATRA_CONNECT_FACEBOOK.CONNECT_PAGES', { count: selectedCount })
        "
        class="!bg-violet-600 hover:!bg-violet-700 !text-white self-start min-h-11"
        :disabled="selectedCount === 0"
        :is-loading="isSubmittingPages"
        @click="connectSelectedPages"
      />
    </div>
  </div>
</template>
