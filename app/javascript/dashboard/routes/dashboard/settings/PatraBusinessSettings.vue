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
const testingWebhook = ref(false);

const autoResolveHours = ref(24);
const webhookUrl = ref('');
const reengageDays = ref(7);
const reengageMessage = ref('');
const cashoutApprovalThreshold = ref(500);
const roundRobinEnabled = ref(true);
const roundRobinMax = ref(50);
const firstResponseLimitMinutes = ref(5);
const resolutionLimitMinutes = ref(60);
const slaAlertsEnabled = ref(true);
const keywordRows = ref([]);

const DEFAULT_REENGAGE_MESSAGE =
  'hey! been a minute 🎰 got any new games you wanna try?';

function mappingToRows(mapping) {
  if (!mapping || typeof mapping !== 'object') return [];
  return Object.entries(mapping).flatMap(([tag, keywords]) =>
    Array.isArray(keywords)
      ? keywords.map(keyword => ({ keyword, tag }))
      : [{ keyword: String(keywords), tag }]
  );
}

function rowsToMapping(rows) {
  const mapping = {};
  rows.forEach(({ keyword, tag }) => {
    const kw = keyword?.trim();
    const tg = tag?.trim();
    if (!kw || !tg) return;
    mapping[tg] ||= [];
    if (!mapping[tg].includes(kw)) mapping[tg].push(kw);
  });
  return mapping;
}

function addKeywordRow() {
  keywordRows.value.push({ keyword: '', tag: '' });
}

function removeKeywordRow(index) {
  keywordRows.value.splice(index, 1);
}

onMounted(async () => {
  try {
    const { data } = await PatraSettingsAPI.get();
    autoResolveHours.value = data.auto_resolve_hours ?? 24;
    webhookUrl.value = data.webhook_url || '';
    reengageDays.value = data.reengage_days ?? 7;
    reengageMessage.value = data.reengage_message || DEFAULT_REENGAGE_MESSAGE;
    cashoutApprovalThreshold.value = data.cashout_approval_threshold ?? 500;
    roundRobinEnabled.value = data.round_robin_enabled ?? true;
    roundRobinMax.value = data.round_robin_max_conversations ?? 50;
    firstResponseLimitMinutes.value = data.first_response_limit_minutes ?? 5;
    resolutionLimitMinutes.value = data.resolution_limit_minutes ?? 60;
    slaAlertsEnabled.value = data.sla_alerts_enabled ?? true;
    keywordRows.value = mappingToRows(data.keyword_tag_mapping);
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
      reengage_days: Number(reengageDays.value) || 7,
      reengage_message: reengageMessage.value,
      cashout_approval_threshold: Number(cashoutApprovalThreshold.value),
      round_robin_enabled: roundRobinEnabled.value,
      round_robin_max_conversations: Number(roundRobinMax.value),
      first_response_limit_minutes: Number(firstResponseLimitMinutes.value),
      resolution_limit_minutes: Number(resolutionLimitMinutes.value),
      sla_alerts_enabled: slaAlertsEnabled.value,
      keyword_tag_mapping: rowsToMapping(keywordRows.value),
    });
    useAlert(t('PATRA.SETTINGS.SAVED'));
  } catch {
    useAlert(t('PATRA.SETTINGS.SAVE_ERROR'));
  } finally {
    saving.value = false;
  }
}

async function testWebhook() {
  testingWebhook.value = true;
  try {
    const { data } = await PatraSettingsAPI.testWebhook();
    useAlert(data.message || t('PATRA.BUSINESS_SETTINGS.WEBHOOK_TEST_SUCCESS'));
  } catch (error) {
    const msg =
      error?.response?.data?.error || t('PATRA.BUSINESS_SETTINGS.WEBHOOK_TEST_ERROR');
    useAlert(msg);
  } finally {
    testingWebhook.value = false;
  }
}
</script>

<template>
  <div class="rounded-xl border border-n-weak bg-n-solid-1 p-4 space-y-6">
    <h2 class="text-base font-semibold text-n-slate-12">
      {{ $t('PATRA.BUSINESS_SETTINGS.TITLE') }}
    </h2>
    <p v-if="loading" class="text-sm text-n-slate-11">{{ $t('PATRA.SETTINGS.LOADING') }}</p>
    <template v-else>
      <div class="space-y-4">
        <NextInput
          v-model="autoResolveHours"
          type="number"
          :label="$t('PATRA.BUSINESS_SETTINGS.AUTO_RESOLVE_HOURS')"
        />

        <div>
          <NextInput v-model="webhookUrl" :label="$t('PATRA.BUSINESS_SETTINGS.WEBHOOK_URL')" />
          <Button
            class="mt-2"
            faded
            sm
            :label="$t('PATRA.BUSINESS_SETTINGS.WEBHOOK_TEST')"
            :is-loading="testingWebhook"
            @click="testWebhook"
          />
        </div>

        <div>
          <h3 class="text-sm font-medium text-n-slate-12">
            {{ $t('PATRA.SETTINGS.REENGAGE_TITLE') }}
          </h3>
          <p class="mt-1 text-sm text-n-slate-11">
            {{ $t('PATRA.SETTINGS.REENGAGE_NOTE') }}
          </p>
          <div class="mt-2 flex items-center gap-2">
            <NextInput v-model="reengageDays" type="number" class="!w-20" />
            <span class="text-sm text-n-slate-11">{{ $t('PATRA.SETTINGS.DAYS_LABEL') }}</span>
          </div>
          <NextInput
            v-model="reengageMessage"
            class="mt-2"
            :label="$t('PATRA.BUSINESS_SETTINGS.REENGAGE_MESSAGE')"
          />
        </div>

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
      </div>

      <div class="space-y-3 border-t border-n-weak pt-4">
        <h3 class="text-sm font-medium text-n-slate-12">
          {{ $t('PATRA.BUSINESS_SETTINGS.SLA_TITLE') }}
        </h3>
        <p class="text-sm text-n-slate-11">{{ $t('PATRA.BUSINESS_SETTINGS.SLA_NOTE') }}</p>
        <NextInput
          v-model="firstResponseLimitMinutes"
          type="number"
          :label="$t('PATRA.BUSINESS_SETTINGS.FIRST_RESPONSE_LIMIT')"
        />
        <NextInput
          v-model="resolutionLimitMinutes"
          type="number"
          :label="$t('PATRA.BUSINESS_SETTINGS.RESOLUTION_LIMIT')"
        />
        <label class="flex items-center gap-2 text-sm text-n-slate-12">
          <input v-model="slaAlertsEnabled" type="checkbox" />
          {{ $t('PATRA.BUSINESS_SETTINGS.SLA_ALERTS') }}
        </label>
      </div>

      <div class="space-y-3 border-t border-n-weak pt-4">
        <h3 class="text-sm font-medium text-n-slate-12">
          {{ $t('PATRA.BUSINESS_SETTINGS.KEYWORD_MAPPING_TITLE') }}
        </h3>
        <p class="text-sm text-n-slate-11">
          {{ $t('PATRA.BUSINESS_SETTINGS.KEYWORD_MAPPING_NOTE') }}
        </p>
        <div class="overflow-x-auto">
          <table class="w-full text-sm">
            <thead>
              <tr class="text-left text-n-slate-11">
                <th class="pb-2 pr-3 font-medium">
                  {{ $t('PATRA.BUSINESS_SETTINGS.KEYWORD') }}
                </th>
                <th class="pb-2 pr-3 font-medium">{{ $t('PATRA.BUSINESS_SETTINGS.TAG') }}</th>
                <th class="pb-2 font-medium">{{ $t('PATRA.BUSINESS_SETTINGS.ACTIONS') }}</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="(row, index) in keywordRows" :key="index">
                <td class="pb-2 pr-3">
                  <NextInput v-model="row.keyword" />
                </td>
                <td class="pb-2 pr-3">
                  <NextInput v-model="row.tag" />
                </td>
                <td class="pb-2">
                  <Button
                    faded
                    sm
                    ruby
                    :label="$t('PATRA.BUSINESS_SETTINGS.REMOVE_ROW')"
                    @click="removeKeywordRow(index)"
                  />
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <Button
          faded
          sm
          :label="$t('PATRA.BUSINESS_SETTINGS.ADD_ROW')"
          @click="addKeywordRow"
        />
      </div>

      <Button :label="$t('PATRA.SETTINGS.SAVE')" :is-loading="saving" @click="save" />
    </template>
  </div>
</template>
