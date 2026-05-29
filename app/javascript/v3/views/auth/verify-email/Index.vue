<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import VueHcaptcha from '@hcaptcha/vue3-hcaptcha';
import { resendConfirmation } from '../../../api/auth';
import Spinner from 'shared/components/Spinner.vue';
import AuthNavBar from '../../../components/Auth/AuthNavBar.vue';

const props = defineProps({
  email: {
    type: String,
    default: '',
  },
});

const { t } = useI18n();
const router = useRouter();
const store = useStore();

if (!props.email) {
  router.push({ name: 'login' });
}

const globalConfig = computed(() => store.getters['globalConfig/get']);
const isResendingEmail = ref(false);
const hCaptcha = ref(null);
let captchaToken = '';

const performResend = async () => {
  isResendingEmail.value = true;
  try {
    await resendConfirmation({
      email: props.email,
      hCaptchaClientResponse: captchaToken,
    });
    useAlert(t('REGISTER.VERIFY_EMAIL.RESEND_SUCCESS'));
  } catch {
    useAlert(t('REGISTER.VERIFY_EMAIL.RESEND_ERROR'));
  } finally {
    isResendingEmail.value = false;
    captchaToken = '';
    if (globalConfig.value.hCaptchaSiteKey) {
      hCaptcha.value.reset();
    }
  }
};

const handleResendEmail = () => {
  if (isResendingEmail.value) return;
  if (globalConfig.value.hCaptchaSiteKey) {
    hCaptcha.value.execute();
  } else {
    performResend();
  }
};

const onCaptchaVerified = token => {
  captchaToken = token;
  performResend();
};

const onCaptchaError = () => {
  isResendingEmail.value = false;
  captchaToken = '';
  hCaptcha.value.reset();
};
</script>

<template>
  <div
    class="relative min-h-screen flex flex-col bg-auth-canvas text-auth-text font-sans overflow-x-hidden max-w-[100vw]"
  >
    <div
      class="auth-grid fixed inset-0 z-0 pointer-events-none [mask-image:radial-gradient(ellipse_90%_60%_at_50%_30%,black_35%,transparent_100%)]"
    />
    <div
      class="auth-mesh fixed top-[-15%] left-1/2 -translate-x-1/2 w-[1100px] h-[700px] z-0 pointer-events-none rounded-full blur-[80px] animate-patra-mesh"
    />

    <AuthNavBar />

    <main
      class="flex-1 flex items-center justify-center px-5 py-12 relative z-10"
    >
      <div
        class="w-full max-w-[440px] relative bg-auth-card-bg backdrop-blur-xl border border-auth-border-hi rounded-3xl p-10 shadow-[0_30px_80px_-20px_rgba(0,0,0,0.5)] animate-card-in auth-card-anim"
      >
        <div class="flex flex-col items-start mb-8">
          <div
            class="w-[46px] h-[46px] rounded-[13px] bg-gradient-to-br from-patra to-patra-deep flex items-center justify-center font-display font-bold text-white text-2xl mb-5 animate-patra-pulse auth-pulse"
          >
            {{ $t('PATRA_AUTH.BRAND_INITIAL') }}
          </div>
          <h1
            class="font-display font-semibold text-[26px] tracking-tight leading-snug mb-2"
          >
            {{ $t('PATRA_AUTH.VERIFY_EMAIL.HEADING') }}
          </h1>
          <p class="text-auth-text-dim text-sm leading-relaxed">
            {{ $t('PATRA_AUTH.VERIFY_EMAIL.SUBHEAD') }}
          </p>
          <p class="mt-3 text-sm text-auth-text-dim">
            {{ $t('REGISTER.VERIFY_EMAIL.DESCRIPTION', { email }) }}
          </p>
        </div>

        <div class="space-y-4">
          <VueHcaptcha
            v-if="globalConfig.hCaptchaSiteKey"
            ref="hCaptcha"
            size="invisible"
            :sitekey="globalConfig.hCaptchaSiteKey"
            @verify="onCaptchaVerified"
            @error="onCaptchaError"
            @expired="onCaptchaError"
            @challenge-expired="onCaptchaError"
            @closed="onCaptchaError"
          />
          <button
            type="button"
            data-testid="resend_email_button"
            class="relative w-full bg-gradient-to-b from-patra to-patra-deep text-white font-medium text-[15px] rounded-xl px-4 py-3.5 mt-1.5 cursor-pointer transition-all shadow-patra-glow hover:shadow-patra-glow-hover hover:brightness-110 hover:-translate-y-px inline-flex items-center justify-center gap-2 disabled:opacity-60 disabled:cursor-not-allowed disabled:hover:translate-y-0"
            :disabled="isResendingEmail"
            @click="handleResendEmail"
          >
            <Spinner v-if="isResendingEmail" color-scheme="primary" size="" />
            {{ $t('REGISTER.VERIFY_EMAIL.RESEND') }}
          </button>
        </div>
      </div>
    </main>

    <div
      class="text-center py-6 text-[11px] text-auth-text-mute font-mono tracking-wider relative z-10"
    >
      {{ $t('PATRA_AUTH.FOOTER') }}
    </div>
  </div>
</template>
