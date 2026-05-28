<script setup>
import { ref, computed, onBeforeMount } from 'vue';
import { useStore } from 'vuex';
import SignupForm from './components/Signup/Form.vue';
import Spinner from 'shared/components/Spinner.vue';
import AuthNavBar from '../../../components/Auth/AuthNavBar.vue';

const store = useStore();

const isLoading = ref(false);
const globalConfig = computed(() => store.getters['globalConfig/get']);
const isAChatwootInstance = computed(
  () => globalConfig.value.installationName === 'Chatwoot'
);

onBeforeMount(() => {
  isLoading.value = isAChatwootInstance.value;
});
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
      v-show="!isLoading"
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
            {{ $t('PATRA_AUTH.SIGNUP.HEADING') }}
          </h1>
          <p class="text-zinc-400 text-sm leading-relaxed">
            {{ $t('PATRA_AUTH.SIGNUP.SUBHEAD') }}
          </p>
          <p class="mt-3 text-sm text-zinc-400">
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
      v-show="isLoading"
      class="flex-1 flex items-center justify-center relative z-10"
    >
      <Spinner color-scheme="primary" size="" />
    </div>

    <div
      class="text-center py-6 text-[11px] text-zinc-500 font-mono tracking-wider relative z-10"
    >
      {{ $t('PATRA_AUTH.FOOTER') }}
    </div>
  </div>
</template>
