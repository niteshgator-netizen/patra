<script>
import { useVuelidate } from '@vuelidate/core';
import { required, minLength } from '@vuelidate/validators';
import { useAlert } from 'dashboard/composables';
import FormInput from '../../../components/Form/Input.vue';
import AuthNavBar from '../../../components/Auth/AuthNavBar.vue';
import { DEFAULT_REDIRECT_URL } from 'dashboard/constants/globals';
import { setNewPassword } from '../../../api/auth';
import Spinner from 'shared/components/Spinner.vue';

export default {
  components: {
    FormInput,
    Spinner,
    AuthNavBar,
  },
  props: {
    resetPasswordToken: { type: String, default: '' },
  },
  setup() {
    return { v$: useVuelidate() };
  },
  data() {
    return {
      // We need to initialize the component with any
      // properties that will be used in it
      credentials: {
        confirmPassword: '',
        password: '',
      },
      newPasswordAPI: {
        message: '',
        showLoading: false,
      },
      error: '',
    };
  },
  mounted() {
    // If url opened without token
    // redirect to login
    if (!this.resetPasswordToken) {
      window.location = DEFAULT_REDIRECT_URL;
    }
  },
  validations: {
    credentials: {
      password: {
        required,
        minLength: minLength(6),
      },
      confirmPassword: {
        required,
        minLength: minLength(6),
        isEqPassword(value) {
          if (value !== this.credentials.password) {
            return false;
          }
          return true;
        },
      },
    },
  },
  methods: {
    showAlertMessage(message) {
      // Reset loading, current selected agent
      this.newPasswordAPI.showLoading = false;
      useAlert(message);
    },
    submitForm() {
      this.newPasswordAPI.showLoading = true;
      const credentials = {
        confirmPassword: this.credentials.confirmPassword,
        password: this.credentials.password,
        resetPasswordToken: this.resetPasswordToken,
      };
      setNewPassword(credentials)
        .then(() => {
          window.location = DEFAULT_REDIRECT_URL;
        })
        .catch(error => {
          this.showAlertMessage(
            error?.message || this.$t('SET_NEW_PASSWORD.API.ERROR_MESSAGE')
          );
        });
    },
  },
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
            {{ $t('PATRA_AUTH.SET_PASSWORD.HEADING') }}
          </h1>
          <p class="text-auth-text-dim text-sm leading-relaxed">
            {{ $t('PATRA_AUTH.SET_PASSWORD.SUBHEAD') }}
          </p>
        </div>

        <form class="space-y-5" @submit.prevent="submitForm">
          <FormInput
            v-model="credentials.password"
            variant="patra"
            class="mt-3"
            name="password"
            type="password"
            :label="$t('LOGIN.PASSWORD.LABEL')"
            :has-error="v$.credentials.password.$error"
            :error-message="$t('SET_NEW_PASSWORD.PASSWORD.ERROR')"
            :placeholder="$t('SET_NEW_PASSWORD.PASSWORD.PLACEHOLDER')"
            @blur="v$.credentials.password.$touch"
          />
          <FormInput
            v-model="credentials.confirmPassword"
            variant="patra"
            class="mt-3"
            name="confirm_password"
            type="password"
            :label="$t('SET_NEW_PASSWORD.CONFIRM_PASSWORD.PLACEHOLDER')"
            :has-error="v$.credentials.confirmPassword.$error"
            :error-message="$t('SET_NEW_PASSWORD.CONFIRM_PASSWORD.ERROR')"
            :placeholder="$t('SET_NEW_PASSWORD.CONFIRM_PASSWORD.PLACEHOLDER')"
            @blur="v$.credentials.confirmPassword.$touch"
          />
          <button
            type="submit"
            data-testid="submit_button"
            class="relative w-full bg-gradient-to-b from-patra to-patra-deep text-white font-medium text-[15px] rounded-xl px-4 py-3.5 mt-1.5 cursor-pointer transition-all shadow-patra-glow hover:shadow-patra-glow-hover hover:brightness-110 hover:-translate-y-px inline-flex items-center justify-center gap-2 disabled:opacity-60 disabled:cursor-not-allowed disabled:hover:translate-y-0"
            :disabled="
              v$.credentials.password.$invalid ||
              v$.credentials.confirmPassword.$invalid ||
              newPasswordAPI.showLoading
            "
          >
            <Spinner
              v-if="newPasswordAPI.showLoading"
              color-scheme="primary"
              size=""
            />
            {{ $t('SET_NEW_PASSWORD.SUBMIT') }}
          </button>
        </form>
      </div>
    </main>

    <div
      class="text-center py-6 text-[11px] text-auth-text-mute font-mono tracking-wider relative z-10"
    >
      {{ $t('PATRA_AUTH.FOOTER') }}
    </div>
  </div>
</template>
