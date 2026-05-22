<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';
import axios from 'axios';
import { useAlert } from 'dashboard/composables';
import { frontendURL } from 'dashboard/helper/URLHelper';
import Button from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useStore();
const alert = useAlert();

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
const selectedIds = ref(new Set());
const errorMessage = ref('');

const apiBase = () => `/api/v1/accounts/${accountId.value}/patra`;

const allSelected = computed(
  () => pages.value.length > 0 && selectedIds.value.size === pages.value.length
);

const selectedCount = computed(() => selectedIds.value.size);

const toggleSelectAll = () => {
  if (allSelected.value) {
    selectedIds.value = new Set();
  } else {
    selectedIds.value = new Set(pages.value.map(p => p.id));
  }
};

const togglePage = id => {
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
    const { data } = await axios.post(`${apiBase()}/fb_connect`, {
      access_token: token,
    });
    pages.value = data.pages || [];
    userAccessToken.value = data.user_access_token || '';
    facebookIdentityId.value = data.facebook_identity_id || null;
    fbUserName.value = data.fb_user_name || '';
    selectedIds.value = new Set(pages.value.map(p => p.id));
  } catch (e) {
    const msg = e.response?.data?.error || e.message;
    errorMessage.value = msg || t('PATRA_CONNECT_FACEBOOK.ERRORS.GENERIC');
  } finally {
    isBusy.value = false;
  }
};

const connectSelectedPages = async () => {
  errorMessage.value = '';
  const selected = pages.value.filter(p => selectedIds.value.has(p.id));
  if (selected.length === 0) {
    alert(t('PATRA_CONNECT_FACEBOOK.ERRORS.SELECT_ONE'));
    return;
  }
  isSubmittingPages.value = true;
  try {
    await axios.post(`${apiBase()}/fb_connect_pages`, {
      user_access_token: userAccessToken.value,
      facebook_identity_id: facebookIdentityId.value,
      pages: selected.map(p => ({
        id: p.id,
        name: p.name,
        access_token: p.access_token,
      })),
    });
    await store.dispatch('inboxes/get');
    alert(t('PATRA_CONNECT_FACEBOOK.SUCCESS'));
    router.push(frontendURL(`accounts/${accountId.value}/settings/inboxes/list`));
  } catch (e) {
    const msg = e.response?.data?.error || e.message;
    errorMessage.value = msg || t('PATRA_CONNECT_FACEBOOK.ERRORS.GENERIC');
  } finally {
    isSubmittingPages.value = false;
  }
};

onMounted(() => {
  store.dispatch('inboxes/get');
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
          class="flex gap-3 items-center p-3 rounded-xl border border-n-weak bg-n-alpha-2 cursor-pointer hover:bg-n-alpha-1"
        >
          <input
            type="checkbox"
            class="rounded border-n-weak text-violet-600 focus:ring-violet-500 shrink-0"
            :checked="isPageSelected(page.id)"
            @change="togglePage(page.id)"
          />
          <img
            v-if="page.picture"
            :src="page.picture"
            :alt="page.name"
            class="size-12 rounded-full object-cover shrink-0 bg-n-slate-4"
          />
          <div class="min-w-0 flex-1">
            <div class="text-sm font-medium text-n-slate-12 truncate">
              {{ page.name }}
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
