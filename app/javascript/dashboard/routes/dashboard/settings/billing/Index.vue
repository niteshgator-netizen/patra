<script setup>
import { computed, onMounted, ref } from 'vue';
import { useRouter } from 'vue-router';
import { useMapGetter, useStore } from 'dashboard/composables/store.js';
import { useAccount } from 'dashboard/composables/useAccount';
import { useCaptain } from 'dashboard/composables/useCaptain';
import { format } from 'date-fns';
import sessionStorage from 'shared/helpers/sessionStorage';

import BillingMeter from './components/BillingMeter.vue';
import BillingCard from './components/BillingCard.vue';
import BillingHeader from './components/BillingHeader.vue';
import DetailItem from './components/DetailItem.vue';
import PurchaseCreditsModal from './components/PurchaseCreditsModal.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import SettingsLayout from '../SettingsLayout.vue';
import ButtonV4 from 'next/button/Button.vue';

const router = useRouter();
const { currentAccount, isOnChatwootCloud } = useAccount();
const {
  captainEnabled,
  captainLimits,
  documentLimits,
  responseLimits,
  fetchLimits,
  isFetchingLimits,
} = useCaptain();

const uiFlags = useMapGetter('accounts/getUIFlags');
const store = useStore();

const BILLING_REFRESH_ATTEMPTED = 'billing_refresh_attempted';

// State for handling refresh attempts and loading
const isWaitingForBilling = ref(false);
const purchaseCreditsModalRef = ref(null);

const customAttributes = computed(() => {
  return currentAccount.value.custom_attributes || {};
});

/**
 * Computed property for plan name
 * @returns {string|undefined}
 */
const planName = computed(() => {
  return customAttributes.value.plan_name;
});

const canPurchaseCredits = computed(() => {
  const plan = planName.value?.toLowerCase();
  return plan && plan !== 'hacker';
});

/**
 * Computed property for subscribed quantity
 * @returns {number|undefined}
 */
const subscribedQuantity = computed(() => {
  return customAttributes.value.subscribed_quantity;
});

const subscriptionRenewsOn = computed(() => {
  if (!customAttributes.value.subscription_ends_on) return '';
  const endDate = new Date(customAttributes.value.subscription_ends_on);
  // return date as 12 Jan, 2034
  return format(endDate, 'dd MMM, yyyy');
});

/**
 * Computed property indicating if user has a billing plan
 * @returns {boolean}
 */
const hasABillingPlan = computed(() => {
  return !!planName.value;
});

const fetchAccountDetails = async () => {
  if (!hasABillingPlan.value) {
    await store.dispatch('accounts/subscription');
  }
  // Always fetch limits for billing page to show credit usage
  fetchLimits();
};

const handleBillingPageLogic = async () => {
  // If self-hosted, redirect to dashboard
  if (!isOnChatwootCloud.value) {
    router.push({ name: 'home' });
    return;
  }

  // Check if we've already attempted a refresh for billing setup
  const billingRefreshAttempted = sessionStorage.get(BILLING_REFRESH_ATTEMPTED);

  // If cloud user, fetch account details first
  await fetchAccountDetails();

  // If still no billing plan after fetch
  if (!hasABillingPlan.value) {
    // If we haven't attempted refresh yet, do it once
    if (!billingRefreshAttempted) {
      isWaitingForBilling.value = true;
      sessionStorage.set(BILLING_REFRESH_ATTEMPTED, true);

      setTimeout(() => {
        window.location.reload();
      }, 5000);
    } else {
      // We've already tried refreshing, so just show the no billing message
      // Clear the flag for future visits
      sessionStorage.remove(BILLING_REFRESH_ATTEMPTED);
    }
  } else {
    // Billing plan found, clear any existing refresh flag
    sessionStorage.remove(BILLING_REFRESH_ATTEMPTED);
  }
};

const onClickBillingPortal = () => {
  store.dispatch('accounts/checkout');
};

const onToggleChatWindow = () => {
  if (window.$chatwoot) {
    window.$chatwoot.toggle();
  }
};

const openPurchaseCreditsModal = () => {
  purchaseCreditsModalRef.value?.open();
};

const handleTopupSuccess = () => {
  // Refresh limits to show updated credit balance
  fetchLimits();
};

onMounted(handleBillingPageLogic);
</script>

<template>
  <div class="pat-page-wrap">
    <div class="pat-page-main">
      <SettingsLayout
        :is-loading="uiFlags.isFetchingItem || isWaitingForBilling"
        :loading-message="
          isWaitingForBilling
            ? $t('BILLING_SETTINGS.NO_BILLING_USER')
            : $t('ATTRIBUTES_MGMT.LOADING')
        "
        :no-records-found="!hasABillingPlan && !isWaitingForBilling"
        :no-records-message="$t('BILLING_SETTINGS.NO_BILLING_USER')"
      >
        <template #header>
          <BaseSettingsHeader
            :title="$t('BILLING_SETTINGS.TITLE')"
            :description="$t('BILLING_SETTINGS.DESCRIPTION')"
            :link-text="$t('BILLING_SETTINGS.VIEW_PRICING')"
            feature-name="billing"
          />
        </template>
        <template #body>
          <section class="grid gap-4">
            <BillingCard
              :title="$t('BILLING_SETTINGS.MANAGE_SUBSCRIPTION.TITLE')"
              :description="
                $t('BILLING_SETTINGS.MANAGE_SUBSCRIPTION.DESCRIPTION')
              "
            >
              <template #action>
                <ButtonV4 sm solid blue @click="onClickBillingPortal">
                  {{ $t('BILLING_SETTINGS.MANAGE_SUBSCRIPTION.BUTTON_TXT') }}
                </ButtonV4>
              </template>
              <div
                v-if="planName || subscribedQuantity || subscriptionRenewsOn"
                class="grid lg:grid-cols-4 sm:grid-cols-3 grid-cols-1 gap-2 divide-x divide-n-weak"
              >
                <DetailItem
                  :label="$t('BILLING_SETTINGS.CURRENT_PLAN.TITLE')"
                  :value="planName"
                />
                <DetailItem
                  v-if="subscribedQuantity"
                  :label="$t('BILLING_SETTINGS.CURRENT_PLAN.SEAT_COUNT')"
                  :value="subscribedQuantity"
                />
                <DetailItem
                  v-if="subscriptionRenewsOn"
                  :label="$t('BILLING_SETTINGS.CURRENT_PLAN.RENEWS_ON')"
                  :value="subscriptionRenewsOn"
                />
              </div>
            </BillingCard>
            <BillingCard
              v-if="captainEnabled"
              :title="$t('BILLING_SETTINGS.CAPTAIN.TITLE')"
              :description="$t('BILLING_SETTINGS.CAPTAIN.DESCRIPTION')"
            >
              <template #action>
                <div class="flex gap-2">
                  <ButtonV4
                    sm
                    flushed
                    slate
                    icon="i-lucide-refresh-cw"
                    :is-loading="isFetchingLimits"
                    @click="fetchLimits"
                  >
                    {{ $t('BILLING_SETTINGS.CAPTAIN.REFRESH_CREDITS') }}
                  </ButtonV4>
                  <ButtonV4
                    v-if="canPurchaseCredits"
                    sm
                    solid
                    blue
                    @click="openPurchaseCreditsModal"
                  >
                    {{ $t('BILLING_SETTINGS.TOPUP.BUY_CREDITS') }}
                  </ButtonV4>
                </div>
              </template>
              <div v-if="captainLimits && responseLimits" class="px-5">
                <BillingMeter
                  :title="$t('BILLING_SETTINGS.CAPTAIN.RESPONSES')"
                  v-bind="responseLimits"
                />
              </div>
              <div v-if="captainLimits && documentLimits" class="px-5">
                <BillingMeter
                  :title="$t('BILLING_SETTINGS.CAPTAIN.DOCUMENTS')"
                  v-bind="documentLimits"
                />
              </div>
            </BillingCard>
            <BillingCard
              v-else
              :title="$t('BILLING_SETTINGS.CAPTAIN.TITLE')"
              :description="$t('BILLING_SETTINGS.CAPTAIN.UPGRADE')"
            >
              <template #action>
                <ButtonV4 sm solid slate @click="onClickBillingPortal">
                  {{ $t('CAPTAIN.PAYWALL.UPGRADE_NOW') }}
                </ButtonV4>
              </template>
            </BillingCard>

            <BillingHeader
              class="px-1 mt-5"
              :title="$t('BILLING_SETTINGS.CHAT_WITH_US.TITLE')"
              :description="$t('BILLING_SETTINGS.CHAT_WITH_US.DESCRIPTION')"
            >
              <ButtonV4
                sm
                solid
                slate
                icon="i-lucide-life-buoy"
                @click="onToggleChatWindow"
              >
                {{ $t('BILLING_SETTINGS.CHAT_WITH_US.BUTTON_TXT') }}
              </ButtonV4>
            </BillingHeader>
          </section>
          <PurchaseCreditsModal
            ref="purchaseCreditsModalRef"
            @success="handleTopupSuccess"
          />
        </template>
      </SettingsLayout>
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
