<script setup>
import SignupForm from './components/Signup/Form.vue';
import AuthNavBar from '../../../components/Auth/AuthNavBar.vue';
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
            {{ $t('PATRA_AUTH.SIGNUP.HEADING') }}
          </h1>
          <p class="text-auth-text-dim text-sm leading-relaxed">
            {{ $t('PATRA_AUTH.SIGNUP.SUBHEAD') }}
          </p>
          <p class="mt-3 text-sm text-auth-text-dim">
            {{ $t('REGISTER.HAVE_AN_ACCOUNT') }}
            <router-link class="text-link text-patra-light" to="/app/login">
              {{ $t('LOGIN.SUBMIT') }}
            </router-link>
          </p>
        </div>
        <SignupForm />
      </div>
    </main>

    <div
      class="text-center py-6 text-[11px] text-auth-text-mute font-mono tracking-wider relative z-10"
    >
      {{ $t('PATRA_AUTH.FOOTER') }}
    </div>
  </div>
</template>
