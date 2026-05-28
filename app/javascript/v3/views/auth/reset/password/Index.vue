<script>
import { useVuelidate } from '@vuelidate/core';
import { useAlert } from 'dashboard/composables';
import { required, minLength, email } from '@vuelidate/validators';
import { useBranding } from 'shared/composables/useBranding';
import FormInput from '../../../../components/Form/Input.vue';
import AuthNavBar from '../../../../components/Auth/AuthNavBar.vue';
import { resetPassword } from '../../../../api/auth';
import Spinner from 'shared/components/Spinner.vue';

export default {
  components: { FormInput, Spinner, AuthNavBar },
  setup() {
    const { replaceInstallationName } = useBranding();
    return { v$: useVuelidate(), replaceInstallationName };
  },
  data() {
    return {
      credentials: { email: '' },
      resetPassword: {
        message: '',
        showLoading: false,
      },
      error: '',
    };
  },
  validations() {
    return {
      credentials: {
        email: {
          required,
          email,
          minLength: minLength(4),
        },
      },
    };
  },
  methods: {
    showAlertMessage(message) {
      // Reset loading, current selected agent
      this.resetPassword.showLoading = false;
      useAlert(message);
    },
    submit() {
      this.resetPassword.showLoading = true;
      resetPassword(this.credentials)
        .then(res => {
          let successMessage = this.$t('RESET_PASSWORD.API.SUCCESS_MESSAGE');
          if (res.data && res.data.message) {
            successMessage = res.data.message;
          }
          this.showAlertMessage(successMessage);
        })
        .catch(error => {
          let errorMessage = this.$t('RESET_PASSWORD.API.ERROR_MESSAGE');
          if (error?.response?.data?.message) {
            errorMessage = error.response.data.message;
          }
          this.showAlertMessage(errorMessage);
        });
    },
  },
};
</script>

<template>
  <div
    class="relative min-h-screen flex flex-col bg-patra-canvas text-white font-sans overflow-x-hidden dark"
  >
    <div
      class="fixed inset-0 z-0 pointer-events-none bg-[linear-gradient(to_right,rgba(255,255,255,0.03)_1px,transparent_1px),linear-gradient(to_bottom,rgba(255,255,255,0.03)_1px,transparent_1px)] bg-[size:40px_40px] [mask-image:radial-gradient(ellipse_90%_60%_at_50%_30%,black_35%,transparent_100%)]"
    />
    <div
      class="fixed top-[-15%] left-1/2 -translate-x-1/2 w-[1100px] h-[700px] z-0 pointer-events-none rounded-full blur-[80px] bg-[radial-gradient(circle_at_30%_30%,rgba(110,86,207,0.22),transparent_55%),radial-gradient(circle_at_70%_60%,rgba(139,92,246,0.14),transparent_55%)] animate-patra-mesh"
    />

    <AuthNavBar />

    <main
      class="flex-1 flex items-center justify-center px-5 py-12 relative z-10"
    >
      <div
        class="w-full max-w-[440px] relative bg-patra-surface/55 backdrop-blur-xl border border-patra-border-hi rounded-3xl p-10 shadow-[0_30px_80px_-20px_rgba(0,0,0,0.5)] animate-card-in"
      >
        <div class="flex flex-col items-start mb-8">
          <div
            class="w-[46px] h-[46px] rounded-[13px] bg-gradient-to-br from-patra to-patra-deep flex items-center justify-center font-display font-bold text-white text-2xl mb-5 animate-patra-pulse"
          >
            {{ $t('PATRA_AUTH.BRAND_INITIAL') }}
          </div>
          <h1
            class="font-display font-semibold text-[26px] tracking-tight leading-snug mb-2"
          >
            {{ $t('PATRA_AUTH.FORGOT.HEADING') }}
          </h1>
          <p class="text-zinc-400 text-sm leading-relaxed">
            {{ $t('PATRA_AUTH.FORGOT.SUBHEAD') }}
          </p>
        </div>

        <form class="space-y-5" @submit.prevent="submit">
          <FormInput
            v-model="credentials.email"
            variant="patra"
            name="email_address"
            :label="$t('LOGIN.EMAIL.LABEL')"
            :has-error="v$.credentials.email.$error"
            :error-message="$t('RESET_PASSWORD.EMAIL.ERROR')"
            :placeholder="$t('RESET_PASSWORD.EMAIL.PLACEHOLDER')"
            @input="v$.credentials.email.$touch"
          />
          <button
            type="submit"
            data-testid="submit_button"
            class="relative w-full bg-gradient-to-b from-patra to-patra-deep text-white font-medium text-[15px] rounded-xl px-4 py-3.5 mt-1.5 cursor-pointer transition-all shadow-patra-glow hover:shadow-patra-glow-hover hover:brightness-110 hover:-translate-y-px inline-flex items-center justify-center gap-2 disabled:opacity-60 disabled:cursor-not-allowed disabled:hover:translate-y-0"
            :disabled="
              v$.credentials.email.$invalid || resetPassword.showLoading
            "
          >
            <Spinner
              v-if="resetPassword.showLoading"
              color-scheme="primary"
              size=""
            />
            {{ $t('RESET_PASSWORD.SUBMIT') }}
          </button>
          <p class="mt-4 text-sm text-zinc-400">
            {{ $t('RESET_PASSWORD.GO_BACK_TO_LOGIN') }}
            <router-link to="/app/login" class="text-link text-patra-light">
              {{ $t('RESET_PASSWORD.CLICK_HERE') }}
            </router-link>
          </p>
        </form>
      </div>
    </main>

    <div
      class="text-center py-6 text-[11px] text-zinc-500 font-mono tracking-wider relative z-10"
    >
      {{ $t('PATRA_AUTH.FOOTER') }}
    </div>
  </div>
</template>
