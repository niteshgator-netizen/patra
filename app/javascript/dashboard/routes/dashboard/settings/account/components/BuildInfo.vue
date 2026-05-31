<script setup>
import { computed } from 'vue';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter } from 'dashboard/composables/store';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import { useI18n } from 'vue-i18n';

import semver from 'semver';

const { t } = useI18n();
const { currentAccount } = useAccount();

const latestChatwootVersion = computed(() => {
  return currentAccount.value.latest_chatwoot_version;
});

const globalConfig = useMapGetter('globalConfig/get');

const hasAnUpdateAvailable = computed(() => {
  if (!semver.valid(latestChatwootVersion.value)) {
    return false;
  }

  return semver.lt(globalConfig.value.appVersion, latestChatwootVersion.value);
});

const gitSha = computed(() => {
  return globalConfig.value.gitSha.substring(0, 7);
});

const copyGitSha = () => {
  copyTextToClipboard(globalConfig.value.gitSha);
};
</script>

<template>
  <span
    v-if="hasAnUpdateAvailable && globalConfig.displayManifest"
    class="update-note"
  >
    {{
      t('GENERAL_SETTINGS.UPDATE_CHATWOOT', {
        latestChatwootVersion: latestChatwootVersion,
      })
    }}
  </span>
  <span class="version">{{
    t('PATRA.SETTINGS.VERSION', { version: globalConfig.appVersion })
  }}</span>
  <span
    v-tooltip="t('COMPONENTS.CODE.BUTTON_TEXT')"
    class="build-id"
    role="button"
    tabindex="0"
    @click="copyGitSha"
    @keydown.enter.space.prevent="copyGitSha"
  >
    {{ t('PATRA.SETTINGS.BUILD', { sha: gitSha }) }}
  </span>
</template>

<style scoped>
.update-note {
  width: 100%;
  margin-bottom: 4px;
}

.version,
.build-id {
  cursor: default;
}

.build-id {
  cursor: pointer;
}

.build-id:hover {
  color: var(--patra-3, #a78bfa);
}
</style>
