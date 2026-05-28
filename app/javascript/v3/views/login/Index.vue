<script>
// utils and composables
import { login } from '../../api/auth';
import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { required, email } from '@vuelidate/validators';
import { useVuelidate } from '@vuelidate/core';
import { SESSION_STORAGE_KEYS } from 'dashboard/constants/sessionStorage';
import SessionStorage from 'shared/helpers/sessionStorage';
import { useBranding } from 'shared/composables/useBranding';

// components
import SimpleDivider from '../../components/Divider/SimpleDivider.vue';
import FormInput from '../../components/Form/Input.vue';
import GoogleOAuthButton from '../../components/GoogleOauth/Button.vue';
import Spinner from 'shared/components/Spinner.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import MfaVerification from 'dashboard/components/auth/MfaVerification.vue';
import AuthNavBar from '../../components/Auth/AuthNavBar.vue';

const ERROR_MESSAGES = {
  'no-account-found': 'LOGIN.OAUTH.NO_ACCOUNT_FOUND',
  'business-account-only': 'LOGIN.OAUTH.BUSINESS_ACCOUNTS_ONLY',
  'saml-authentication-failed': 'LOGIN.SAML.API.ERROR_MESSAGE',
  'saml-not-enabled': 'LOGIN.SAML.API.ERROR_MESSAGE',
};

const IMPERSONATION_URL_SEARCH_KEY = 'impersonation';
const USER_NOT_CONFIRMED_ERROR_CODE = 'user_not_confirmed';

export default {
  components: {
    FormInput,
    GoogleOAuthButton,
    Spinner,
    SimpleDivider,
    MfaVerification,
    Icon,
    AuthNavBar,
  },
  props: {
    ssoAuthToken: { type: String, default: '' },
    ssoAccountId: { type: String, default: '' },
    ssoConversationId: { type: String, default: '' },
    email: { type: String, default: '' },
    authError: { type: String, default: '' },
  },
  setup() {
    const { replaceInstallationName } = useBranding();
    return {
      replaceInstallationName,
      v$: useVuelidate(),
    };
  },
  data() {
    return {
      // We need to initialize the component with any
      // properties that will be used in it
      credentials: {
        email: '',
        password: '',
      },
      loginApi: {
        message: '',
        showLoading: false,
        hasErrored: false,
      },
      error: '',
      mfaRequired: false,
      mfaToken: null,
    };
  },
  validations() {
    return {
      credentials: {
        password: {
          required,
        },
        email: {
          required,
          email,
        },
      },
    };
  },
  computed: {
    ...mapGetters({ globalConfig: 'globalConfig/get' }),
    allowedLoginMethods() {
      return window.chatwootConfig.allowedLoginMethods || ['email'];
    },
    showGoogleOAuth() {
      return (
        this.allowedLoginMethods.includes('google_oauth') &&
        Boolean(window.chatwootConfig.googleOAuthClientId)
      );
    },
    showSignupLink() {
      return window.chatwootConfig.signupEnabled === 'true';
    },
    showSamlLogin() {
      return this.allowedLoginMethods.includes('saml');
    },
  },
  created() {
    if (this.ssoAuthToken) {
      this.submitLogin();
    }
    if (this.authError) {
      const messageKey = ERROR_MESSAGES[this.authError] ?? 'LOGIN.API.UNAUTH';
      // Use a method to get the translated text to avoid dynamic key warning
      const translatedMessage = this.getTranslatedMessage(messageKey);
      useAlert(translatedMessage);
      // wait for idle state
      this.requestIdleCallbackPolyfill(() => {
        // Remove the error query param from the url
        const { query } = this.$route;
        this.$router.replace({ query: { ...query, error: undefined } });
      });
    }
  },
  methods: {
    getTranslatedMessage(key) {
      // Avoid dynamic key warning by handling each case explicitly
      switch (key) {
        case 'LOGIN.OAUTH.NO_ACCOUNT_FOUND':
          return this.$t('LOGIN.OAUTH.NO_ACCOUNT_FOUND');
        case 'LOGIN.OAUTH.BUSINESS_ACCOUNTS_ONLY':
          return this.$t('LOGIN.OAUTH.BUSINESS_ACCOUNTS_ONLY');
        case 'LOGIN.API.UNAUTH':
        default:
          return this.$t('LOGIN.API.UNAUTH');
      }
    },
    // TODO: Remove this when Safari gets wider support
    // Ref: https://caniuse.com/requestidlecallback
    //
    requestIdleCallbackPolyfill(callback) {
      if (window.requestIdleCallback) {
        window.requestIdleCallback(callback);
      } else {
        // Fallback for safari
        // Using a delay of 0 allows the callback to be executed asynchronously
        // in the next available event loop iteration, similar to requestIdleCallback
        setTimeout(callback, 0);
      }
    },
    showAlertMessage(message) {
      // Reset loading, current selected agent
      this.loginApi.showLoading = false;
      this.loginApi.message = message;
      useAlert(this.loginApi.message);
    },
    handleImpersonation() {
      // Detects impersonation mode via URL and sets a session flag to prevent user settings changes during impersonation.
      const urlParams = new URLSearchParams(window.location.search);
      const impersonation = urlParams.get(IMPERSONATION_URL_SEARCH_KEY);
      if (impersonation) {
        SessionStorage.set(SESSION_STORAGE_KEYS.IMPERSONATION_USER, true);
      }
    },
    submitLogin() {
      this.loginApi.hasErrored = false;
      this.loginApi.showLoading = true;

      const credentials = {
        email: this.email
          ? decodeURIComponent(this.email)
          : this.credentials.email,
        password: this.credentials.password,
        sso_auth_token: this.ssoAuthToken,
        ssoAccountId: this.ssoAccountId,
        ssoConversationId: this.ssoConversationId,
      };

      login(credentials)
        .then(result => {
          // Check if MFA is required
          if (result?.mfaRequired) {
            this.loginApi.showLoading = false;
            this.mfaRequired = true;
            this.mfaToken = result.mfaToken;
            return;
          }

          this.handleImpersonation();
          this.showAlertMessage(this.$t('LOGIN.API.SUCCESS_MESSAGE'));
        })
        .catch(response => {
          if (response?.errorCode === USER_NOT_CONFIRMED_ERROR_CODE) {
            this.loginApi.showLoading = false;
            this.$router.push({
              name: 'auth_verify_email',
              state: { email: credentials.email },
            });
            return;
          }

          // Reset URL Params if the authentication is invalid
          if (this.email) {
            window.location = '/app/login';
          }
          this.loginApi.hasErrored = true;
          this.showAlertMessage(
            response?.message || this.$t('LOGIN.API.UNAUTH')
          );
        });
    },
    submitFormLogin() {
      if (this.v$.credentials.email.$invalid && !this.email) {
        this.showAlertMessage(this.$t('LOGIN.EMAIL.ERROR'));
        return;
      }

      this.submitLogin();
    },
    handleMfaVerified() {
      // MFA verification successful, continue with login
      this.handleImpersonation();
      window.location = '/app';
    },
    handleMfaCancel() {
      // User cancelled MFA, reset state
      this.mfaRequired = false;
      this.mfaToken = null;
      this.credentials.password = '';
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
        :class="{ 'animate-wiggle': loginApi.hasErrored }"
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
            {{ $t('PATRA_AUTH.LOGIN.HEADING') }}
          </h1>
          <p class="text-zinc-400 text-sm leading-relaxed">
            {{ $t('PATRA_AUTH.LOGIN.SUBHEAD') }}
          </p>
        </div>

        <section v-if="mfaRequired">
          <MfaVerification
            :mfa-token="mfaToken"
            @verified="handleMfaVerified"
            @cancel="handleMfaCancel"
          />
        </section>

        <template v-else>
          <div v-if="!email">
            <div class="flex flex-col gap-4">
              <GoogleOAuthButton v-if="showGoogleOAuth" />
              <div v-if="showSamlLogin" class="text-center">
                <router-link
                  to="/app/login/sso"
                  class="inline-flex justify-center w-full px-3.5 py-3 items-center bg-patra-surface-2 text-white border border-patra-border rounded-xl text-sm font-medium transition-all hover:bg-patra-surface-3 hover:border-patra-border-hi hover:-translate-y-px no-underline"
                >
                  <Icon
                    icon="i-lucide-lock-keyhole"
                    class="size-5 text-zinc-400"
                  />
                  <span class="ml-2">
                    {{ $t('LOGIN.SAML.LABEL') }}
                  </span>
                </router-link>
              </div>
              <SimpleDivider
                v-if="showGoogleOAuth || showSamlLogin"
                :label="$t('COMMON.OR')"
              />
            </div>
            <form class="space-y-5" @submit.prevent="submitFormLogin">
              <FormInput
                v-model="credentials.email"
                variant="patra"
                name="email_address"
                type="text"
                data-testid="email_input"
                :tabindex="1"
                required
                :label="$t('LOGIN.EMAIL.LABEL')"
                :placeholder="$t('LOGIN.EMAIL.PLACEHOLDER')"
                :has-error="v$.credentials.email.$error"
                @input="v$.credentials.email.$touch"
              />
              <FormInput
                v-model="credentials.password"
                variant="patra"
                type="password"
                name="password"
                data-testid="password_input"
                required
                :tabindex="2"
                :label="$t('LOGIN.PASSWORD.LABEL')"
                :placeholder="$t('LOGIN.PASSWORD.PLACEHOLDER')"
                :has-error="v$.credentials.password.$error"
                @input="v$.credentials.password.$touch"
              >
                <p v-if="!globalConfig.disableUserProfileUpdate">
                  <router-link
                    to="auth/reset/password"
                    class="text-sm text-link"
                    tabindex="4"
                  >
                    {{ $t('LOGIN.FORGOT_PASSWORD') }}
                  </router-link>
                </p>
              </FormInput>
              <button
                type="submit"
                data-testid="submit_button"
                class="relative w-full bg-gradient-to-b from-patra to-patra-deep text-white font-medium text-[15px] rounded-xl px-4 py-3.5 mt-1.5 cursor-pointer transition-all shadow-patra-glow hover:shadow-patra-glow-hover hover:brightness-110 hover:-translate-y-px inline-flex items-center justify-center gap-2 disabled:opacity-60 disabled:cursor-not-allowed disabled:hover:translate-y-0"
                :tabindex="3"
                :disabled="loginApi.showLoading"
              >
                <Spinner
                  v-if="loginApi.showLoading"
                  color-scheme="primary"
                  size=""
                />
                {{ $t('LOGIN.SUBMIT') }}
              </button>
            </form>
            <p
              v-if="showSignupLink"
              class="mt-6 text-sm text-center text-zinc-400"
            >
              {{ $t('COMMON.OR') }}
              <router-link
                to="auth/signup"
                class="lowercase text-link text-patra-light"
              >
                {{ $t('LOGIN.CREATE_NEW_ACCOUNT') }}
              </router-link>
            </p>
          </div>
          <div v-else class="flex items-center justify-center py-8">
            <Spinner color-scheme="primary" size="" />
          </div>
        </template>
      </div>
    </main>

    <div
      class="text-center py-6 text-[11px] text-zinc-500 font-mono tracking-wider relative z-10"
    >
      {{ $t('PATRA_AUTH.FOOTER') }}
    </div>
  </div>
</template>
