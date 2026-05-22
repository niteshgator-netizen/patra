<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { dynamicTime } from 'shared/helpers/timeHelper';
import { copyTextToClipboard } from 'shared/helpers/clipboard';

import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ConfirmButton from 'dashboard/components-next/button/ConfirmButton.vue';
import Input from 'dashboard/components-next/input/Input.vue';

defineOptions({
  name: 'MetaAppSettings',
});

const { t } = useI18n();
const router = useRouter();
const { accountId, accountScopedRoute } = useAccount();

const isLoading = ref(true);
const isSaving = ref(false);
const isDisconnecting = ref(false);
const hasByocApp = ref(false);
const savedAppId = ref('');
const savedAppName = ref('');
const validatedAt = ref(null);
const appIdInput = ref('');
const appSecretInput = ref('');
const errorMessage = ref('');
const successMessage = ref('');

const apiBase = () => `/api/v1/accounts/${accountId.value}/patra`;

const redirectUri = computed(() => {
  if (typeof window === 'undefined') return '';
  return `${window.location.origin}/patra/oauth/callback`;
});

const appNameStorageKey = computed(
  () => `patra_meta_app_name_${accountId.value}`
);

const formattedValidatedAt = computed(() => {
  if (!validatedAt.value) return '';
  return dynamicTime(validatedAt.value);
});

const loadCachedAppName = () => {
  try {
    savedAppName.value = localStorage.getItem(appNameStorageKey.value) || '';
  } catch {
    savedAppName.value = '';
  }
};

const cacheAppName = name => {
  try {
    if (name) {
      localStorage.setItem(appNameStorageKey.value, name);
    } else {
      localStorage.removeItem(appNameStorageKey.value);
    }
  } catch {
    // ignore storage errors
  }
};

const fetchMetaApp = async () => {
  isLoading.value = true;
  errorMessage.value = '';
  try {
    const { data } = await window.axios.get(`${apiBase()}/meta_app`);
    hasByocApp.value = !!data?.has_byoc_app;
    savedAppId.value = data?.app_id || '';
    validatedAt.value = data?.app_validated_at || null;
    if (hasByocApp.value) {
      loadCachedAppName();
    } else {
      savedAppName.value = '';
    }
  } catch {
    errorMessage.value = t('META_APP_SETTINGS.ERRORS.LOAD_FAILED');
    hasByocApp.value = false;
  } finally {
    isLoading.value = false;
  }
};

const saveMetaApp = async () => {
  errorMessage.value = '';
  successMessage.value = '';
  isSaving.value = true;
  try {
    const { data } = await window.axios.post(`${apiBase()}/meta_app`, {
      app_id: appIdInput.value.trim(),
      app_secret: appSecretInput.value.trim(),
    });
    savedAppName.value = data?.app_name || '';
    cacheAppName(savedAppName.value);
    successMessage.value = t('META_APP_SETTINGS.EMPTY.SAVE_SUCCESS', {
      name: savedAppName.value || data?.app_id,
    });
    appSecretInput.value = '';
    await fetchMetaApp();
  } catch (e) {
    errorMessage.value =
      e.response?.data?.error || t('META_APP_SETTINGS.ERRORS.SAVE_FAILED');
  } finally {
    isSaving.value = false;
  }
};

const disconnectMetaApp = async () => {
  errorMessage.value = '';
  isDisconnecting.value = true;
  try {
    await window.axios.delete(`${apiBase()}/meta_app`);
    hasByocApp.value = false;
    savedAppId.value = '';
    savedAppName.value = '';
    validatedAt.value = null;
    appIdInput.value = '';
    appSecretInput.value = '';
    cacheAppName('');
    useAlert(t('META_APP_SETTINGS.CONFIGURED.DISCONNECT_SUCCESS'));
  } catch (e) {
    errorMessage.value =
      e.response?.data?.error ||
      t('META_APP_SETTINGS.ERRORS.DISCONNECT_FAILED');
  } finally {
    isDisconnecting.value = false;
  }
};

const copyRedirectUri = async () => {
  await copyTextToClipboard(redirectUri.value);
  useAlert(t('META_APP_SETTINGS.EMPTY.COPY_URI_SUCCESS'));
};

const openMetaConsole = () => {
  window.open('https://developers.facebook.com/apps/create', '_blank');
};

const openMetaApps = () => {
  window.open('https://developers.facebook.com/apps/', '_blank');
};

const goToConnectFacebook = () => {
  router.push(accountScopedRoute('patra_connect_facebook'));
};

onMounted(() => {
  fetchMetaApp();
});
</script>

<template>
  <SettingsLayout
    :is-loading="isLoading"
    :loading-message="$t('ATTRIBUTES_MGMT.LOADING')"
  >
    <template #header>
      <BaseSettingsHeader
        :title="$t('META_APP_SETTINGS.TITLE')"
        :description="$t('META_APP_SETTINGS.DESCRIPTION')"
      />
    </template>

    <template #body>
      <div class="max-w-2xl flex flex-col gap-6 px-6 pb-8">
        <div
          v-if="errorMessage"
          class="text-sm text-n-ruby-11 bg-n-ruby-3/30 rounded-lg px-3 py-2"
        >
          {{ errorMessage }}
        </div>

        <div
          v-if="successMessage && !hasByocApp"
          class="text-sm text-n-teal-11 bg-n-teal-3/30 rounded-lg px-3 py-2"
        >
          {{ successMessage }}
        </div>

        <!-- STATE B: configured -->
        <div
          v-if="hasByocApp"
          class="flex flex-col gap-5 p-5 rounded-xl border border-n-weak bg-n-alpha-2"
        >
          <h2 class="text-lg font-semibold text-n-slate-12">
            {{ $t('META_APP_SETTINGS.CONFIGURED.HEADING') }}
          </h2>

          <dl class="flex flex-col gap-3 text-sm">
            <div v-if="savedAppName" class="flex flex-col gap-0.5">
              <dt class="text-n-slate-10">
                {{ $t('META_APP_SETTINGS.CONFIGURED.APP_NAME') }}
              </dt>
              <dd class="font-medium text-n-slate-12">{{ savedAppName }}</dd>
            </div>
            <div class="flex flex-col gap-0.5">
              <dt class="text-n-slate-10">
                {{ $t('META_APP_SETTINGS.CONFIGURED.APP_ID') }}
              </dt>
              <dd class="font-mono text-n-slate-12">{{ savedAppId }}</dd>
            </div>
            <div v-if="validatedAt" class="flex flex-col gap-0.5">
              <dt class="text-n-slate-10">
                {{
                  $t('META_APP_SETTINGS.CONFIGURED.VALIDATED', {
                    date: formattedValidatedAt,
                  })
                }}
              </dt>
            </div>
          </dl>

          <div class="flex flex-wrap gap-3">
            <ConfirmButton
              :label="$t('META_APP_SETTINGS.CONFIGURED.DISCONNECT')"
              :confirm-label="$t('META_APP_SETTINGS.CONFIGURED.DISCONNECT_CONFIRM')"
              :confirm-hint="$t('META_APP_SETTINGS.CONFIGURED.DISCONNECT_HINT')"
              color="slate"
              confirm-color="ruby"
              :is-loading="isDisconnecting"
              @click="disconnectMetaApp"
            />
            <Button
              :label="$t('META_APP_SETTINGS.CONFIGURED.CONNECT_PAGES')"
              class="!bg-violet-600 hover:!bg-violet-700 !text-white"
              @click="goToConnectFacebook"
            />
          </div>
        </div>

        <!-- STATE A: empty -->
        <div v-else class="flex flex-col gap-8">
          <div>
            <h2 class="text-lg font-semibold text-n-slate-12">
              {{ $t('META_APP_SETTINGS.EMPTY.HEADING') }}
            </h2>
            <p class="text-sm text-n-slate-11 mt-1">
              {{ $t('META_APP_SETTINGS.EMPTY.SUBHEADING') }}
            </p>
          </div>

          <!-- Section 1 -->
          <section class="flex gap-4">
            <span
              class="flex size-8 shrink-0 items-center justify-center rounded-full bg-violet-600 text-sm font-semibold text-white"
            >
              1
            </span>
            <div class="flex flex-col gap-3 min-w-0 flex-1">
              <h3 class="text-base font-medium text-n-slate-12">
                {{ $t('META_APP_SETTINGS.EMPTY.SECTION_1_TITLE') }}
              </h3>
              <p class="text-sm text-n-slate-11">
                {{ $t('META_APP_SETTINGS.EMPTY.SECTION_1_HELP') }}
              </p>
              <Button
                :label="$t('META_APP_SETTINGS.EMPTY.OPEN_CONSOLE')"
                faded
                slate
                class="self-start"
                @click="openMetaConsole"
              />
            </div>
          </section>

          <!-- Section 2 -->
          <section class="flex gap-4">
            <span
              class="flex size-8 shrink-0 items-center justify-center rounded-full bg-violet-600 text-sm font-semibold text-white"
            >
              2
            </span>
            <div class="flex flex-col gap-3 min-w-0 flex-1">
              <h3 class="text-base font-medium text-n-slate-12">
                {{ $t('META_APP_SETTINGS.EMPTY.SECTION_2_TITLE') }}
              </h3>
              <p class="text-sm text-n-slate-11">
                {{ $t('META_APP_SETTINGS.EMPTY.SECTION_2_HELP') }}
              </p>
              <div
                class="flex flex-col sm:flex-row sm:items-center gap-2 p-3 rounded-lg bg-n-solid-3 border border-n-weak"
              >
                <code
                  class="text-xs font-mono break-all text-n-slate-12 flex-1"
                >
                  {{ redirectUri }}
                </code>
                <Button
                  :label="$t('META_APP_SETTINGS.EMPTY.COPY_URI')"
                  size="sm"
                  faded
                  slate
                  class="shrink-0"
                  @click="copyRedirectUri"
                />
              </div>
              <Button
                :label="$t('META_APP_SETTINGS.EMPTY.OPEN_APPS')"
                faded
                slate
                class="self-start"
                @click="openMetaApps"
              />
            </div>
          </section>

          <!-- Section 3 -->
          <section class="flex gap-4">
            <span
              class="flex size-8 shrink-0 items-center justify-center rounded-full bg-violet-600 text-sm font-semibold text-white"
            >
              3
            </span>
            <div class="flex flex-col gap-4 min-w-0 flex-1">
              <h3 class="text-base font-medium text-n-slate-12">
                {{ $t('META_APP_SETTINGS.EMPTY.SECTION_3_TITLE') }}
              </h3>
              <Input
                v-model="appIdInput"
                :label="$t('META_APP_SETTINGS.EMPTY.APP_ID_LABEL')"
                :placeholder="$t('META_APP_SETTINGS.EMPTY.APP_ID_PLACEHOLDER')"
              />
              <Input
                v-model="appSecretInput"
                type="password"
                :label="$t('META_APP_SETTINGS.EMPTY.APP_SECRET_LABEL')"
                :placeholder="
                  $t('META_APP_SETTINGS.EMPTY.APP_SECRET_PLACEHOLDER')
                "
              />
              <Button
                :label="$t('META_APP_SETTINGS.EMPTY.TEST_SAVE')"
                class="!bg-violet-600 hover:!bg-violet-700 !text-white self-start min-h-11"
                :is-loading="isSaving"
                :disabled="!appIdInput.trim() || !appSecretInput.trim()"
                @click="saveMetaApp"
              />
            </div>
          </section>
        </div>
      </div>
    </template>
  </SettingsLayout>
</template>
