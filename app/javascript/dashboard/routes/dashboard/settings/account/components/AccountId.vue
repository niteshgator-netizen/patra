<script setup>
import { computed } from 'vue';
import { useAccount } from 'dashboard/composables/useAccount';
import { useI18n } from 'vue-i18n';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import { useAlert } from 'dashboard/composables';

const { t } = useI18n();
const { currentAccount } = useAccount();

const getAccountId = computed(() => currentAccount.value.id.toString());

const copyAccountId = () => {
  copyTextToClipboard(getAccountId.value);
  useAlert(t('COMPONENTS.CODE.BUTTON_TEXT'));
};
</script>

<template>
  <span
    v-tooltip="t('GENERAL_SETTINGS.FORM.ACCOUNT_ID.NOTE')"
    class="footer-id"
    role="button"
    tabindex="0"
    @click="copyAccountId"
    @keydown.enter.space.prevent="copyAccountId"
  >
    {{ $t('PATRA.SETTINGS.ACCOUNT_ID', { id: getAccountId }) }}
  </span>
</template>

<style scoped>
.footer-id {
  cursor: pointer;
}

.footer-id:hover {
  color: var(--patra-3, #a78bfa);
}
</style>
