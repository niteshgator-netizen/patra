<script setup>
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useAlert } from 'dashboard/composables';
import { useMapGetter, useStore } from 'dashboard/composables/store.js';
import { useAccount } from 'dashboard/composables/useAccount';
import PortalSettings from 'dashboard/components-next/HelpCenter/Pages/PortalSettingsPage/PortalSettings.vue';

const SSL_STATUS_FETCH_INTERVAL = 5000;

const { t } = useI18n();
const store = useStore();
const route = useRoute();
const router = useRouter();
const { isOnChatwootCloud } = useAccount();

const { updateUISettings } = useUISettings();

const portals = useMapGetter('portals/allPortals');
const isFetching = useMapGetter('portals/isFetchingPortals');
const getPortalBySlug = useMapGetter('portals/portalBySlug');

const getNextAvailablePortal = deletedPortalSlug =>
  portals.value?.find(portal => portal.slug !== deletedPortalSlug) ?? null;

const getDefaultLocale = slug => {
  return getPortalBySlug.value(slug)?.meta?.default_locale;
};

const fetchSSLStatus = () => {
  if (!isOnChatwootCloud.value) return;

  const { portalSlug } = route.params;
  store.dispatch('portals/sslStatus', {
    portalSlug,
  });
};

const fetchPortalAndItsCategories = async (slug, locale) => {
  const selectedPortalParam = { portalSlug: slug, locale };
  await Promise.all([
    store.dispatch('portals/index'),
    store.dispatch('portals/show', selectedPortalParam),
    store.dispatch('categories/index', selectedPortalParam),
    store.dispatch('agents/get'),
    store.dispatch('inboxes/get'),
  ]);
};

const updateRouteAfterDeletion = async deletedPortalSlug => {
  const nextPortal = getNextAvailablePortal(deletedPortalSlug);
  if (nextPortal) {
    const {
      slug,
      meta: { default_locale: defaultLocale },
    } = nextPortal;
    await fetchPortalAndItsCategories(slug, defaultLocale);
    router.push({
      name: 'portals_articles_index',
      params: { portalSlug: slug, locale: defaultLocale },
    });
  } else {
    router.push({ name: 'portals_new' });
  }
};

const refreshPortalRoute = async (newSlug, defaultLocale) => {
  // This is to refresh the portal route and update the UI settings
  // If there is slug change, this will be called to refresh the route and UI settings
  await fetchPortalAndItsCategories(newSlug, defaultLocale);
  updateUISettings({
    last_active_portal_slug: newSlug,
    last_active_locale_code: defaultLocale,
  });
  await router.replace({
    name: 'portals_settings_index',
    params: { portalSlug: newSlug },
  });
};

const updatePortalSettings = async portalObj => {
  const { portalSlug } = route.params;
  try {
    const defaultLocale = getDefaultLocale(portalSlug);
    await store.dispatch('portals/update', {
      ...portalObj,
      portalSlug: portalSlug || portalObj?.slug,
    });

    // If there is a slug change, this will refresh the route and update the UI settings
    if (portalObj?.slug && portalSlug !== portalObj.slug) {
      await refreshPortalRoute(portalObj.slug, defaultLocale);
    }
    useAlert(
      t('HELP_CENTER.PORTAL_SETTINGS.API.UPDATE_PORTAL.SUCCESS_MESSAGE')
    );
  } catch (error) {
    useAlert(
      error?.message ||
        t('HELP_CENTER.PORTAL_SETTINGS.API.UPDATE_PORTAL.ERROR_MESSAGE')
    );
  }
};

const deletePortal = async selectedPortalForDelete => {
  const { slug } = selectedPortalForDelete;
  try {
    await store.dispatch('portals/delete', { portalSlug: slug });
    await updateRouteAfterDeletion(slug);
    useAlert(
      t('HELP_CENTER.PORTAL.PORTAL_SETTINGS.DELETE_PORTAL.API.DELETE_SUCCESS')
    );
  } catch (error) {
    useAlert(
      error?.message ||
        t('HELP_CENTER.PORTAL.PORTAL_SETTINGS.DELETE_PORTAL.API.DELETE_ERROR')
    );
  }
};

const handleSendCnameInstructions = async payload => {
  try {
    await store.dispatch('portals/sendCnameInstructions', payload);
    useAlert(
      t(
        'HELP_CENTER.PORTAL.PORTAL_SETTINGS.SEND_CNAME_INSTRUCTIONS.API.SUCCESS_MESSAGE'
      )
    );
  } catch (error) {
    useAlert(
      error?.message ||
        t(
          'HELP_CENTER.PORTAL.PORTAL_SETTINGS.SEND_CNAME_INSTRUCTIONS.API.ERROR_MESSAGE'
        )
    );
  }
};

const handleUpdatePortal = updatePortalSettings;
const handleUpdatePortalConfiguration = portalObj => {
  updatePortalSettings(portalObj);

  // If custom domain is added or updated, fetch SSL status after a delay of 5 seconds (only on Chatwoot cloud)
  if (portalObj?.custom_domain && isOnChatwootCloud.value) {
    setTimeout(() => {
      fetchSSLStatus();
    }, SSL_STATUS_FETCH_INTERVAL);
  }
};
const handleDeletePortal = deletePortal;
</script>

<template>
  <div class="pat-page-wrap">
    <div class="pat-page-main">
      <PortalSettings
        :portals="portals"
        :is-fetching="isFetching"
        @update-portal="handleUpdatePortal"
        @update-portal-configuration="handleUpdatePortalConfiguration"
        @delete-portal="handleDeletePortal"
        @refresh-status="fetchSSLStatus"
        @send-cname-instructions="handleSendCnameInstructions"
      />
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
