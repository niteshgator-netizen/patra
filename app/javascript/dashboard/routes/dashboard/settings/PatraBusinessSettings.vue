<script setup>
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import PatraSettingsAPI from 'dashboard/api/patraSettings';
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

function toggleRoundRobin() {
  roundRobinEnabled.value = !roundRobinEnabled.value;
}

function toggleSlaAlerts() {
  slaAlertsEnabled.value = !slaAlertsEnabled.value;
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
      error?.response?.data?.error ||
      t('PATRA.BUSINESS_SETTINGS.WEBHOOK_TEST_ERROR');
    useAlert(msg);
  } finally {
    testingWebhook.value = false;
  }
}
</script>

<template>
  <div class="patra-business">
    <p v-if="loading" class="card loading-card">
      {{ $t('PATRA.SETTINGS.LOADING') }}
    </p>

    <template v-else>
      <div class="card">
        <div class="card-t display">
          <span class="dot" />
          {{ $t('PATRA.BUSINESS_SETTINGS.TITLE') }}
        </div>

        <div class="fld">
          <label>{{ $t('PATRA.BUSINESS_SETTINGS.AUTO_RESOLVE_HOURS') }}</label>
          <NextInput
            v-model="autoResolveHours"
            type="number"
            class="pat-input"
          />
        </div>

        <div class="fld">
          <label>{{ $t('PATRA.BUSINESS_SETTINGS.WEBHOOK_URL') }}</label>
          <NextInput v-model="webhookUrl" class="pat-input" />
          <p class="hint">{{ $t('PATRA.BUSINESS_SETTINGS.WEBHOOK_HINT') }}</p>
        </div>

        <button
          type="button"
          class="btn sm webhook-test"
          :disabled="testingWebhook"
          @click="testWebhook"
        >
          {{
            testingWebhook
              ? $t('PATRA.SETTINGS.SAVING')
              : $t('PATRA.BUSINESS_SETTINGS.WEBHOOK_TEST')
          }}
        </button>

        <div class="fld">
          <label>{{ $t('PATRA.BUSINESS_SETTINGS.REENGAGE_DAYS') }}</label>
          <NextInput v-model="reengageDays" type="number" class="pat-input" />
        </div>

        <div class="fld">
          <label>{{ $t('PATRA.BUSINESS_SETTINGS.REENGAGE_MESSAGE') }}</label>
          <textarea v-model="reengageMessage" class="pat-textarea" rows="2" />
        </div>

        <div class="fld">
          <label>{{ $t('PATRA.BUSINESS_SETTINGS.CASHOUT_APPROVAL') }}</label>
          <NextInput
            v-model="cashoutApprovalThreshold"
            type="number"
            class="pat-input"
          />
          <p class="hint">{{ $t('PATRA.BUSINESS_SETTINGS.CASHOUT_HINT') }}</p>
        </div>

        <div class="tog-row">
          <div class="tr-l">
            <div class="tt">
              {{ $t('PATRA.BUSINESS_SETTINGS.ROUND_ROBIN') }}
            </div>
            <div class="ts">
              {{ $t('PATRA.BUSINESS_SETTINGS.ROUND_ROBIN_SUB') }}
            </div>
          </div>
          <div
            class="sw"
            :class="{ off: !roundRobinEnabled }"
            role="switch"
            :aria-checked="roundRobinEnabled"
            tabindex="0"
            @click="toggleRoundRobin"
            @keydown.enter.space.prevent="toggleRoundRobin"
          >
            <i />
          </div>
        </div>

        <div class="fld round-robin-max">
          <label>{{ $t('PATRA.BUSINESS_SETTINGS.ROUND_ROBIN_MAX') }}</label>
          <NextInput v-model="roundRobinMax" type="number" class="pat-input" />
        </div>
      </div>

      <div class="card">
        <div class="card-t display">
          <span class="dot" />
          {{ $t('PATRA.BUSINESS_SETTINGS.SLA_TITLE') }}
        </div>
        <p class="persona-note">{{ $t('PATRA.BUSINESS_SETTINGS.SLA_NOTE') }}</p>

        <div class="fld row sla-row">
          <div>
            <label>{{
              $t('PATRA.BUSINESS_SETTINGS.FIRST_RESPONSE_LIMIT')
            }}</label>
            <NextInput
              v-model="firstResponseLimitMinutes"
              type="number"
              class="pat-input"
            />
          </div>
          <div>
            <label>{{ $t('PATRA.BUSINESS_SETTINGS.RESOLUTION_LIMIT') }}</label>
            <NextInput
              v-model="resolutionLimitMinutes"
              type="number"
              class="pat-input"
            />
          </div>
        </div>

        <div class="tog-row">
          <div class="tr-l">
            <div class="tt">{{ $t('PATRA.BUSINESS_SETTINGS.SLA_ALERTS') }}</div>
            <div class="ts">
              {{ $t('PATRA.BUSINESS_SETTINGS.SLA_ALERTS_SUB') }}
            </div>
          </div>
          <div
            class="sw"
            :class="{ off: !slaAlertsEnabled }"
            role="switch"
            :aria-checked="slaAlertsEnabled"
            tabindex="0"
            @click="toggleSlaAlerts"
            @keydown.enter.space.prevent="toggleSlaAlerts"
          >
            <i />
          </div>
        </div>
      </div>

      <div class="card">
        <div class="card-t display">
          <span class="dot" />
          {{ $t('PATRA.BUSINESS_SETTINGS.KEYWORD_MAPPING_TITLE') }}
        </div>
        <p class="persona-note">
          {{ $t('PATRA.BUSINESS_SETTINGS.KEYWORD_MAPPING_NOTE') }}
        </p>

        <div class="kw-head">
          <span>{{ $t('PATRA.BUSINESS_SETTINGS.KEYWORD') }}</span>
          <span>{{ $t('PATRA.BUSINESS_SETTINGS.TAG') }}</span>
          <span />
        </div>

        <div v-for="(row, index) in keywordRows" :key="index" class="kw-row">
          <input v-model="row.keyword" type="text" class="kw-input" />
          <input v-model="row.tag" type="text" class="kw-input" />
          <button type="button" class="kw-del" @click="removeKeywordRow(index)">
            {{ $t('PATRA.BUSINESS_SETTINGS.REMOVE_ROW') }}
          </button>
        </div>

        <button type="button" class="btn sm" @click="addKeywordRow">
          {{ $t('PATRA.BUSINESS_SETTINGS.ADD_ROW') }}
        </button>

        <div class="save-wrap">
          <button
            type="button"
            class="btn primary"
            :disabled="saving"
            @click="save"
          >
            {{
              saving ? $t('PATRA.SETTINGS.SAVING') : $t('PATRA.SETTINGS.SAVE')
            }}
          </button>
        </div>
      </div>
    </template>
  </div>
</template>

<style scoped>
.patra-business {
  display: contents;
}

.display {
  font-family: 'Space Grotesk', sans-serif;
}

.card {
  position: relative;
  isolation: isolate;
  background: var(--surface, #0c0b12);
  border: 1px solid var(--border, #171520);
  border-radius: 16px;
  padding: 22px;
  margin-bottom: 16px;
}

.loading-card {
  font-size: 13px;
  color: var(--text-3, #75727f);
}

.card-t {
  font-weight: 600;
  font-size: 15px;
  display: flex;
  align-items: center;
  gap: 8px;
  margin-bottom: 18px;
}

.card-t .dot {
  width: 7px;
  height: 7px;
  border-radius: 50%;
  background: var(--patra-2, #8b5cf6);
  box-shadow: 0 0 8px var(--patra-glow, rgba(110, 86, 207, 0.55));
}

.persona-note {
  font-size: 12.5px;
  color: var(--text-3, #75727f);
  margin: -6px 0 14px;
}

.fld {
  margin-bottom: 16px;
}

.fld label {
  display: block;
  font-size: 12.5px;
  color: var(--text-2, #a8a6b6);
  margin-bottom: 6px;
  font-weight: 500;
}

.fld .hint {
  font-size: 11px;
  color: var(--text-4, #54515e);
  margin-top: 5px;
}

.fld.row {
  display: grid;
  gap: 12px;
}

.sla-row {
  grid-template-columns: 1fr 1fr;
}

.round-robin-max {
  margin-top: 14px;
}

.fld :deep(.pat-input input) {
  width: 100%;
  background: var(--canvas, #050409) !important;
  border: 1px solid var(--border, #171520) !important;
  border-radius: 10px !important;
  padding: 10px 13px !important;
  color: var(--text, #ededf2) !important;
  font-size: 13px !important;
  box-shadow: none !important;
}

.fld :deep(.pat-input input:focus) {
  border-color: var(--patra, #6e56cf) !important;
  box-shadow: 0 0 0 3px rgba(110, 86, 207, 0.11) !important;
}

.pat-textarea {
  width: 100%;
  background: var(--canvas, #050409);
  border: 1px solid var(--border, #171520);
  border-radius: 10px;
  padding: 10px 13px;
  color: var(--text, #ededf2);
  font-size: 13px;
  outline: none;
  transition: all 0.25s;
  font-family: 'Inter', sans-serif;
  resize: vertical;
}

.pat-textarea:focus {
  border-color: var(--patra, #6e56cf);
  box-shadow: 0 0 0 3px rgba(110, 86, 207, 0.11);
}

.webhook-test {
  margin-bottom: 16px;
}

.tog-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 12px 0;
  border-bottom: 1px solid var(--border, #171520);
}

.tog-row:last-child {
  border: none;
}

.tog-row .tr-l .tt {
  font-size: 13.5px;
  font-weight: 500;
  color: var(--text, #ededf2);
}

.tog-row .tr-l .ts {
  font-size: 11.5px;
  color: var(--text-3, #75727f);
  margin-top: 2px;
}

.sw {
  width: 38px;
  height: 22px;
  border-radius: 12px;
  background: linear-gradient(
    135deg,
    var(--patra, #6e56cf),
    var(--patra-2, #8b5cf6)
  );
  position: relative;
  cursor: pointer;
  flex-shrink: 0;
  box-shadow: 0 0 12px var(--patra-glow, rgba(110, 86, 207, 0.55));
  transition: all 0.3s;
}

.sw i {
  position: absolute;
  top: 2px;
  right: 2px;
  width: 18px;
  height: 18px;
  border-radius: 50%;
  background: #fff;
  transition: all 0.3s;
}

.sw.off {
  background: var(--surface-4, #252233);
  box-shadow: none;
}

.sw.off i {
  right: auto;
  left: 2px;
}

.kw-head {
  display: grid;
  grid-template-columns: 1fr 1fr auto;
  gap: 10px;
  font-size: 11px;
  color: var(--text-4, #54515e);
  font-family: 'JetBrains Mono', monospace;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  margin-bottom: 8px;
}

.kw-row {
  display: grid;
  grid-template-columns: 1fr 1fr auto;
  gap: 10px;
  margin-bottom: 9px;
  align-items: center;
}

.kw-input {
  background: var(--canvas, #050409);
  border: 1px solid var(--border, #171520);
  border-radius: 9px;
  padding: 9px 12px;
  color: var(--text, #ededf2);
  font-size: 13px;
  outline: none;
  font-family: 'Inter', sans-serif;
}

.kw-input:focus {
  border-color: var(--patra, #6e56cf);
}

.kw-del {
  color: var(--red, #f85149);
  font-size: 12px;
  cursor: pointer;
  padding: 6px 10px;
  border: 1px solid rgba(248, 81, 73, 0.3);
  border-radius: 8px;
  transition: all 0.2s;
  background: transparent;
  white-space: nowrap;
}

.kw-del:hover {
  background: var(--red, #f85149);
  color: #fff;
}

.btn {
  font-size: 13px;
  font-weight: 600;
  padding: 10px 18px;
  border-radius: 10px;
  border: 1px solid var(--border-hi, #2e2940);
  background: var(--surface-2, #131119);
  color: var(--text, #ededf2);
  cursor: pointer;
  transition: all 0.22s cubic-bezier(0.34, 1.56, 0.64, 1);
}

.btn:hover:not(:disabled) {
  transform: translateY(-2px);
  box-shadow: 0 6px 16px rgba(0, 0, 0, 0.3);
  border-color: var(--patra, #6e56cf);
}

.btn:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}

.btn.sm {
  padding: 7px 13px;
  font-size: 12px;
}

.btn.primary {
  background: linear-gradient(
    135deg,
    var(--patra, #6e56cf),
    var(--patra-deep, #5b45b0)
  );
  border-color: transparent;
  color: #fff;
  box-shadow: 0 4px 14px var(--patra-glow, rgba(110, 86, 207, 0.55));
}

.btn.primary:hover:not(:disabled) {
  filter: brightness(1.12);
}

.save-wrap {
  margin-top: 18px;
}
</style>
