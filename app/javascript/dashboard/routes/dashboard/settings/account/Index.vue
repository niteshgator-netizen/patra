<script>
import { useVuelidate } from '@vuelidate/core';
import { required } from '@vuelidate/validators';
import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useConfig } from 'dashboard/composables/useConfig';
import { useAccount } from 'dashboard/composables/useAccount';
import { FEATURE_FLAGS } from '../../../../featureFlags';
import NextInput from 'next/input/Input.vue';
import AccountId from './components/AccountId.vue';
import BuildInfo from './components/BuildInfo.vue';
import AccountDelete from './components/AccountDelete.vue';
import AudioTranscription from './components/AudioTranscription.vue';
import PatraAutomationSettings from './components/PatraAutomationSettings.vue';
import PatraBusinessSettings from '../PatraBusinessSettings.vue';

const INDUSTRIES = [
  { slug: 'sweepstakes', label: 'Social Gaming', persona: 'Patra AI' },
  { slug: 'real_estate', label: 'Real Estate', persona: 'Mia' },
  { slug: 'retail', label: 'Retail / E-commerce', persona: 'Ava' },
  { slug: 'spa', label: 'Spa / Wellness', persona: 'Sofia' },
  { slug: 'restaurant', label: 'Restaurant / Food', persona: 'Marco' },
  { slug: 'healthcare', label: 'Healthcare', persona: 'Nadia' },
  { slug: 'auto', label: 'Auto / Dealership', persona: 'Max' },
  { slug: 'fitness', label: 'Fitness / Gym', persona: 'Jax' },
  { slug: 'services', label: 'Home Services', persona: 'Sam' },
  { slug: 'education', label: 'Education', persona: 'Leo' },
  { slug: 'legal', label: 'Legal', persona: 'Ellis' },
  { slug: 'hotel', label: 'Hotel / Hospitality', persona: 'Olivia' },
];

export default {
  components: {
    AccountId,
    BuildInfo,
    AccountDelete,
    AudioTranscription,
    PatraAutomationSettings,
    PatraBusinessSettings,
    NextInput,
  },
  setup() {
    const { updateUISettings, uiSettings } = useUISettings();
    const { enabledLanguages } = useConfig();
    const { accountId } = useAccount();
    const v$ = useVuelidate();

    return { updateUISettings, uiSettings, v$, enabledLanguages, accountId };
  },
  data() {
    return {
      id: '',
      name: '',
      locale: 'en',
      domain: '',
      supportEmail: '',
      industrySlug: 'sweepstakes',
      features: {},
      industries: INDUSTRIES,
    };
  },
  validations: {
    name: {
      required,
    },
    locale: {
      required,
    },
  },
  computed: {
    ...mapGetters({
      getAccount: 'accounts/getAccount',
      uiFlags: 'accounts/getUIFlags',
      isFeatureEnabledonAccount: 'accounts/isFeatureEnabledonAccount',
      isOnChatwootCloud: 'globalConfig/isOnChatwootCloud',
    }),
    showAudioTranscriptionConfig() {
      return this.isFeatureEnabledonAccount(
        this.accountId,
        FEATURE_FLAGS.CAPTAIN
      );
    },
    languagesSortedByCode() {
      const enabledLanguages = [...this.enabledLanguages];
      return enabledLanguages.sort((l1, l2) =>
        l1.iso_639_1_code.localeCompare(l2.iso_639_1_code)
      );
    },
    isUpdating() {
      return this.uiFlags.isUpdating;
    },
    featureInboundEmailEnabled() {
      return !!this.features?.inbound_emails;
    },
    featureCustomReplyDomainEnabled() {
      return (
        this.featureInboundEmailEnabled && !!this.features.custom_reply_domain
      );
    },
    featureCustomReplyEmailEnabled() {
      return (
        this.featureInboundEmailEnabled && !!this.features.custom_reply_email
      );
    },
    currentAccount() {
      return this.getAccount(this.accountId) || {};
    },
  },
  mounted() {
    this.initializeAccount();
  },
  methods: {
    async initializeAccount() {
      try {
        const {
          name,
          locale,
          id,
          domain,
          support_email,
          features,
          industry_slug,
        } = this.getAccount(this.accountId);

        const effectiveLocale = this.uiSettings?.locale || locale;
        if (effectiveLocale) {
          this.$root.$i18n.locale = effectiveLocale;
        }
        this.name = name;
        this.locale = locale;
        this.id = id;
        this.domain = domain;
        this.supportEmail = support_email;
        this.industrySlug = industry_slug || 'sweepstakes';
        this.features = features;
      } catch (error) {
        // Ignore error
      }
    },

    async updateAccount() {
      this.v$.$touch();
      if (this.v$.$invalid) {
        useAlert(this.$t('GENERAL_SETTINGS.FORM.ERROR'));
        return;
      }
      try {
        await this.$store.dispatch('accounts/update', {
          locale: this.locale,
          name: this.name,
          domain: this.domain,
          support_email: this.supportEmail,
          industry_slug: this.industrySlug,
        });
        const updatedLocale = this.uiSettings?.locale || this.locale;
        if (updatedLocale) {
          this.$root.$i18n.locale = updatedLocale;
        }
        this.getAccount(this.id).locale = this.locale;
        useAlert(this.$t('GENERAL_SETTINGS.UPDATE.SUCCESS'));
      } catch (error) {
        useAlert(this.$t('GENERAL_SETTINGS.UPDATE.ERROR'));
      }
    },

    onSpotlightMove(e) {
      const el = this.$refs.spotlight;
      if (!el) return;
      el.style.left = `${e.clientX}px`;
      el.style.top = `${e.clientY}px`;
      el.style.opacity = '1';
    },

    onSpotlightLeave() {
      const el = this.$refs.spotlight;
      if (el) el.style.opacity = '0';
    },

    onCardGlow(e) {
      const card = e.target.closest('.card');
      if (!card) return;
      const rect = card.getBoundingClientRect();
      card.style.setProperty('--gx', `${e.clientX - rect.left}px`);
      card.style.setProperty('--gy', `${e.clientY - rect.top}px`);
    },
  },
};
</script>

<template>
  <div
    class="account-wrap"
    @mousemove="onSpotlightMove"
    @mouseleave="onSpotlightLeave"
  >
    <div id="spotlight" ref="spotlight" />
    <div class="mesh" />

    <div class="account-main" @mousemove="onCardGlow">
      <div class="sec-head">
        <h1 class="display">{{ $t('GENERAL_SETTINGS.TITLE') }}</h1>
        <div class="sub">{{ $t('PATRA.SETTINGS.ACCOUNT_SUBTITLE') }}</div>
      </div>

      <div v-if="uiFlags.isFetchingItem" class="card">
        <p class="loading-note">{{ $t('PATRA.SETTINGS.LOADING') }}</p>
      </div>

      <div v-if="!uiFlags.isFetchingItem" class="card">
        <div class="card-t display">
          <span class="dot" />
          {{ $t('GENERAL_SETTINGS.FORM.GENERAL_SECTION.TITLE') }}
        </div>
        <form @submit.prevent="updateAccount">
          <div class="fld">
            <label for="account-name">{{
              $t('GENERAL_SETTINGS.FORM.NAME.LABEL')
            }}</label>
            <NextInput
              id="account-name"
              v-model="name"
              type="text"
              class="pat-input"
              :placeholder="$t('GENERAL_SETTINGS.FORM.NAME.PLACEHOLDER')"
              @blur="v$.name.$touch"
            />
            <p v-if="v$.name.$error" class="hint err">
              {{ $t('GENERAL_SETTINGS.FORM.NAME.ERROR') }}
            </p>
          </div>

          <div class="fld">
            <label for="site-language">{{
              $t('GENERAL_SETTINGS.FORM.LANGUAGE.LABEL')
            }}</label>
            <select id="site-language" v-model="locale" class="pat-select">
              <option
                v-for="lang in languagesSortedByCode"
                :key="lang.iso_639_1_code"
                :value="lang.iso_639_1_code"
              >
                {{ lang.name }}
              </option>
            </select>
            <p v-if="v$.locale.$error" class="hint err">
              {{ $t('GENERAL_SETTINGS.FORM.LANGUAGE.ERROR') }}
            </p>
          </div>

          <div class="fld">
            <label for="industry">{{ $t('PATRA.SETTINGS.INDUSTRY') }}</label>
            <select id="industry" v-model="industrySlug" class="pat-select">
              <option
                v-for="industry in industries"
                :key="industry.slug"
                :value="industry.slug"
              >
                {{ industry.label }}
              </option>
            </select>
          </div>

          <p class="persona-note">
            {{ $t('PATRA.SETTINGS.PERSONA_NOTE') }}
            <b>{{ $t('PATRA.SETTINGS.PERSONA_NAME') }}</b>
          </p>

          <div v-if="featureCustomReplyDomainEnabled" class="fld">
            <label for="custom-domain">{{
              $t('GENERAL_SETTINGS.FORM.DOMAIN.LABEL')
            }}</label>
            <NextInput
              id="custom-domain"
              v-model="domain"
              type="text"
              class="pat-input"
              :placeholder="$t('GENERAL_SETTINGS.FORM.DOMAIN.PLACEHOLDER')"
            />
            <p class="hint">
              <template v-if="featureInboundEmailEnabled">
                {{ $t('GENERAL_SETTINGS.FORM.FEATURES.INBOUND_EMAIL_ENABLED') }}
              </template>
              <template v-if="featureCustomReplyDomainEnabled">
                {{
                  $t(
                    'GENERAL_SETTINGS.FORM.FEATURES.CUSTOM_EMAIL_DOMAIN_ENABLED'
                  )
                }}
              </template>
            </p>
          </div>

          <div v-if="featureCustomReplyEmailEnabled" class="fld">
            <label for="support-email">{{
              $t('GENERAL_SETTINGS.FORM.SUPPORT_EMAIL.LABEL')
            }}</label>
            <NextInput
              id="support-email"
              v-model="supportEmail"
              type="text"
              class="pat-input"
              :placeholder="
                $t('GENERAL_SETTINGS.FORM.SUPPORT_EMAIL.PLACEHOLDER')
              "
            />
          </div>

          <button type="submit" class="btn primary" :disabled="isUpdating">
            {{
              isUpdating
                ? $t('PATRA.SETTINGS.SAVING')
                : $t('GENERAL_SETTINGS.SUBMIT')
            }}
          </button>
        </form>
      </div>

      <PatraAutomationSettings v-if="!uiFlags.isFetchingItem" />
      <PatraBusinessSettings v-if="!uiFlags.isFetchingItem" />

      <AudioTranscription v-if="showAudioTranscriptionConfig" />

      <AccountDelete v-if="!uiFlags.isFetchingItem && isOnChatwootCloud" />

      <div class="footer-meta">
        <AccountId />
        <BuildInfo />
      </div>
    </div>
  </div>
</template>

<style scoped>
.account-wrap {
  --canvas: #050409;
  --surface: #0c0b12;
  --surface-2: #131119;
  --surface-3: #1b1925;
  --surface-4: #252233;
  --border: #171520;
  --border-hi: #2e2940;
  --patra: #6e56cf;
  --patra-2: #8b5cf6;
  --patra-3: #a78bfa;
  --patra-deep: #5b45b0;
  --patra-glow: rgba(110, 86, 207, 0.55);
  --text: #ededf2;
  --text-2: #a8a6b6;
  --text-3: #75727f;
  --text-4: #54515e;
  --red: #f85149;
  --mesh-1: rgba(110, 86, 207, 0.16);
  --mesh-2: rgba(139, 92, 246, 0.1);
  --mesh-3: rgba(236, 72, 153, 0.05);

  position: relative;
  min-height: 100%;
  color: var(--text);
  font-family: 'Inter', sans-serif;
  background: var(--canvas);
  overflow: hidden;
}

.display {
  font-family: 'Space Grotesk', sans-serif;
}

#spotlight {
  position: fixed;
  width: 460px;
  height: 460px;
  border-radius: 50%;
  background: radial-gradient(
    circle,
    rgba(110, 86, 207, 0.16),
    rgba(110, 86, 207, 0.04) 42%,
    transparent 66%
  );
  pointer-events: none;
  z-index: 0;
  transform: translate(-50%, -50%);
  opacity: 0;
  transition: opacity 0.5s;
  mix-blend-mode: screen;
  filter: blur(12px);
}

.mesh {
  position: fixed;
  inset: 0;
  pointer-events: none;
  z-index: 0;
  overflow: hidden;
}

.mesh::before,
.mesh::after {
  content: '';
  position: absolute;
  border-radius: 50%;
  filter: blur(100px);
}

.mesh::before {
  top: -15%;
  right: -5%;
  width: 700px;
  height: 560px;
  background:
    radial-gradient(circle at 40% 40%, var(--mesh-1), transparent 60%),
    radial-gradient(circle at 70% 70%, var(--mesh-2), transparent 60%);
  animation: meshA 22s ease-in-out infinite alternate;
}

.mesh::after {
  bottom: -20%;
  left: 10%;
  width: 560px;
  height: 500px;
  background: radial-gradient(
    circle at 50% 50%,
    var(--mesh-3),
    transparent 65%
  );
  animation: meshB 28s ease-in-out infinite alternate;
}

@keyframes meshA {
  0% {
    transform: translate(0, 0) scale(1);
  }
  100% {
    transform: translate(-50px, 40px) scale(1.12) rotate(8deg);
  }
}

@keyframes meshB {
  0% {
    transform: translate(0, 0) scale(1);
  }
  100% {
    transform: translate(40px, -30px) scale(1.1);
  }
}

.account-main {
  position: relative;
  z-index: 1;
  padding: 26px 32px 60px;
  max-width: 760px;
}

.sec-head {
  margin-bottom: 22px;
}

.sec-head h1 {
  font-weight: 600;
  font-size: 23px;
  margin: 0;
}

.sec-head .sub {
  font-size: 13px;
  color: var(--text-3);
  margin-top: 4px;
}

.card {
  position: relative;
  isolation: isolate;
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 16px;
  padding: 22px;
  margin-bottom: 16px;
  transition:
    transform 0.35s cubic-bezier(0.34, 1.56, 0.64, 1),
    box-shadow 0.35s,
    border-color 0.25s;
}

.card::before {
  content: '';
  position: absolute;
  inset: 0;
  border-radius: inherit;
  pointer-events: none;
  opacity: 0;
  transition: opacity 0.3s;
  background: radial-gradient(
    260px circle at var(--gx, 50%) var(--gy, 50%),
    rgba(110, 86, 207, 0.15),
    transparent 70%
  );
  z-index: -1;
}

.card:hover::before {
  opacity: 1;
}

.card:hover {
  transform: translateY(-4px) scale(1.008);
  box-shadow:
    0 18px 40px -14px rgba(0, 0, 0, 0.55),
    0 0 26px rgba(110, 86, 207, 0.18);
  border-color: var(--patra);
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
  background: var(--patra-2);
  box-shadow: 0 0 8px var(--patra-glow);
}

.fld {
  margin-bottom: 16px;
}

.fld label {
  display: block;
  font-size: 12.5px;
  color: var(--text-2);
  margin-bottom: 6px;
  font-weight: 500;
}

.fld .hint {
  font-size: 11px;
  color: var(--text-4);
  margin-top: 5px;
}

.fld .hint.err {
  color: var(--red);
}

.persona-note {
  font-size: 12.5px;
  color: var(--text-3);
  margin: -6px 0 14px;
}

.persona-note b {
  color: var(--patra-3);
}

.pat-select {
  width: 100%;
  background: var(--canvas);
  border: 1px solid var(--border);
  border-radius: 10px;
  padding: 10px 13px;
  color: var(--text);
  font-size: 13px;
  outline: none;
  transition: all 0.25s;
  font-family: 'Inter', sans-serif;
}

.pat-select:focus {
  border-color: var(--patra);
  box-shadow: 0 0 0 3px rgba(110, 86, 207, 0.11);
}

.fld :deep(.pat-input input),
.fld :deep(.pat-input textarea) {
  width: 100%;
  background: var(--canvas) !important;
  border: 1px solid var(--border) !important;
  border-radius: 10px !important;
  padding: 10px 13px !important;
  color: var(--text) !important;
  font-size: 13px !important;
  box-shadow: none !important;
}

.fld :deep(.pat-input input:focus),
.fld :deep(.pat-input textarea:focus) {
  border-color: var(--patra) !important;
  box-shadow: 0 0 0 3px rgba(110, 86, 207, 0.11) !important;
}

.btn {
  font-size: 13px;
  font-weight: 600;
  padding: 10px 18px;
  border-radius: 10px;
  border: 1px solid var(--border-hi);
  background: var(--surface-2);
  color: var(--text);
  cursor: pointer;
  transition: all 0.22s cubic-bezier(0.34, 1.56, 0.64, 1);
}

.btn:hover:not(:disabled) {
  transform: translateY(-2px);
  box-shadow: 0 6px 16px rgba(0, 0, 0, 0.3);
  border-color: var(--patra);
}

.btn:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}

.btn.primary {
  background: linear-gradient(135deg, var(--patra), var(--patra-deep));
  border-color: transparent;
  color: #fff;
  box-shadow: 0 4px 14px var(--patra-glow);
}

.btn.primary:hover:not(:disabled) {
  filter: brightness(1.12);
}

.loading-note {
  font-size: 13px;
  color: var(--text-3);
  margin: 0;
}

.footer-meta {
  font-size: 11px;
  color: var(--text-4);
  font-family: 'JetBrains Mono', monospace;
  margin-top: 20px;
  display: flex;
  gap: 16px;
  flex-wrap: wrap;
}
</style>
