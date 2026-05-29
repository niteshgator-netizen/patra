<script>
import { DEFAULT_REDIRECT_URL } from 'dashboard/constants/globals';
import { verifyPasswordToken } from '../../../api/auth';
import Spinner from 'shared/components/Spinner.vue';
import AuthNavBar from '../../../components/Auth/AuthNavBar.vue';

export default {
  components: { Spinner, AuthNavBar },
  props: {
    confirmationToken: {
      type: String,
      default: '',
    },
  },
  mounted() {
    this.confirmToken();
  },
  methods: {
    async confirmToken() {
      try {
        await verifyPasswordToken({
          confirmationToken: this.confirmationToken,
        });
        window.location = DEFAULT_REDIRECT_URL;
      } catch (error) {
        window.location = DEFAULT_REDIRECT_URL;
      }
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
        class="w-full max-w-[440px] relative bg-auth-card-bg backdrop-blur-xl border border-auth-border-hi rounded-3xl p-10 shadow-[0_30px_80px_-20px_rgba(0,0,0,0.5)] animate-card-in auth-card-anim text-center"
      >
        <div
          class="w-[46px] h-[46px] rounded-[13px] bg-gradient-to-br from-patra to-patra-deep flex items-center justify-center font-display font-bold text-white text-2xl mb-5 animate-patra-pulse auth-pulse mx-auto"
        >
          {{ $t('PATRA_AUTH.BRAND_INITIAL') }}
        </div>
        <Spinner color-scheme="primary" size="" />
        <div class="ml-2 text-auth-text-dim mt-4 text-sm">
          {{ $t('CONFIRM_EMAIL') }}
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
