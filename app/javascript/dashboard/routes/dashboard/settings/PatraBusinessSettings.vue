<script setup>
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import PatraSettingsAPI from 'dashboard/api/patraSettings';
import Button from 'dashboard/components-next/button/Button.vue';
import NextInput from 'next/input/Input.vue';

const { t } = useI18n();
const loading = ref(true);
const saving = ref(false);

const autoResolveHours = ref(24);
const webhookUrl = ref('');
const reengageMessage = ref('');
const cashoutApprovalThreshold = ref(500);
const roundRobinEnabled = ref(true);
const roundRobinMax = ref(50);

onMounted(async () => {
  try {
    const { data } = await PatraSettingsAPI.get();
    autoResolveHours.value = data.auto_resolve_hours ?? 24;
    webhookUrl.value = data.webhook_url || '';
    reengageMessage.value = data.reengage_message || '';
    cashoutApprovalThreshold.value = data.cashout_approval_threshold ?? 500;
    roundRobinEnabled.value = data.round_robin_enabled ?? true;
    roundRobinMax.value = data.round_robin_max_conversations ?? 50;
  } finally {
    loading.value = false;
  }
});

async function save() {
  saving.value = true;
  try {
    await PatraSettingsAPI.update({
      auto_resolve_hours: Number(autoResolveHours.value),
      webhook_url: webhookUrl.value,
      reengage_message: reengageMessage.value,
      cashout_approval_threshold: Number(cashoutApprovalThreshold.value),
      round_robin_enabled: roundRobinEnabled.value,
      round_robin_max_conversations: Number(roundRobinMax.value),
    });
    useAlert(t('PATRA.SETTINGS.SAVED'));
  } catch {
    useAlert(t('PATRA.SETTINGS.SAVE_ERROR'));
  } finally {
    saving.value = false;
  }
}
</script>

<template>
  <div class="rounded-xl border border-n-weak bg-n-solid-1 p-4 space-y-4">
    <h2 class="text-base font-semibold text-n-slate-12">
      {{ $t('PATRA.BUSINESS_SETTINGS.TITLE') }}
    </h2>
    <p v-if="loading" class="text-sm text-n-slate-11">{{ $t('PATRA.SETTINGS.LOADING') }}</p>
    <template v-else>
      <NextInput
        v-model="autoResolveHours"
        type="number"
        :label="$t('PATRA.BUSINESS_SETTINGS.AUTO_RESOLVE_HOURS')"
      />
      <NextInput v-model="webhookUrl" :label="$t('PATRA.BUSINESS_SETTINGS.WEBHOOK_URL')" />
      <NextInput
        v-model="reengageMessage"
        :label="$t('PATRA.BUSINESS_SETTINGS.REENGAGE_MESSAGE')"
      />
      <NextInput
        v-model="cashoutApprovalThreshold"
        type="number"
        :label="$t('PATRA.BUSINESS_SETTINGS.CASHOUT_APPROVAL')"
      />
      <label class="flex items-center gap-2 text-sm text-n-slate-12">
        <input v-model="roundRobinEnabled" type="checkbox" />
        {{ $t('PATRA.BUSINESS_SETTINGS.ROUND_ROBIN') }}
      </label>
      <NextInput
        v-model="roundRobinMax"
        type="number"
        :label="$t('PATRA.BUSINESS_SETTINGS.ROUND_ROBIN_MAX')"
      />
      <Button :label="$t('PATRA.SETTINGS.SAVE')" :is-loading="saving" @click="save" />
    </template>
  </div>
</template>
