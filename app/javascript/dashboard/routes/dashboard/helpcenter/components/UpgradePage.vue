<script>
import { mapGetters } from 'vuex';
import wootConstants from 'dashboard/constants/globals';
import NextButton from 'dashboard/components-next/button/Button.vue';

export default {
  components: {
    NextButton,
  },
  data() {
    return {
      helpCenterDocsURL: wootConstants.HELP_CENTER_DOCS_URL,
      upgradeFeature: [
        {
          key: 1,
          title: this.$t('HELP_CENTER.UPGRADE_PAGE.FEATURES.PORTALS.TITLE'),
          icon: 'book-copy',
          description: this.$t(
            'HELP_CENTER.UPGRADE_PAGE.FEATURES.PORTALS.DESCRIPTION'
          ),
        },
        {
          key: 2,
          title: this.$t('HELP_CENTER.UPGRADE_PAGE.FEATURES.LOCALES.TITLE'),
          icon: 'globe-line',
          description: this.$t(
            'HELP_CENTER.UPGRADE_PAGE.FEATURES.LOCALES.DESCRIPTION'
          ),
        },
        {
          key: 3,
          title: this.$t('HELP_CENTER.UPGRADE_PAGE.FEATURES.SEO.TITLE'),
          icon: 'heart-handshake',
          description: this.$t(
            'HELP_CENTER.UPGRADE_PAGE.FEATURES.SEO.DESCRIPTION'
          ),
        },
        {
          key: 4,
          title: this.$t('HELP_CENTER.UPGRADE_PAGE.FEATURES.API.TITLE'),
          icon: 'search-check',
          description: this.$t(
            'HELP_CENTER.UPGRADE_PAGE.FEATURES.API.DESCRIPTION'
          ),
        },
      ],
    };
  },
  computed: {
    ...mapGetters({
      accountId: 'getCurrentAccountId',
      isOnChatwootCloud: 'globalConfig/isOnChatwootCloud', // Pending change text
    }),
  },
  methods: {
    openBillingPage() {
      this.$router.push({
        name: 'billing_settings_index',
        params: { accountId: this.accountId },
      });
    },
    openHelpCenterDocs() {
      window.open(this.helpCenterDocsURL, '_blank');
    },
  },
};
</script>

<template>
  <div class="pat-page-wrap">
    <div class="pat-page-main">
      <div
        class="flex flex-col gap-12 sm:gap-16 items-center justify-center py-0 px-4 w-full min-h-screen max-w-full overflow-auto bg-n-surface-1"
      >
        <div class="flex flex-col justify-start sm:justify-center gap-6">
          <div class="flex flex-col gap-1.5 items-start sm:items-center">
            <h1
              class="text-n-slate-12 text-left sm:text-center text-4xl sm:text-5xl mb-6 font-semibold"
            >
              {{ $t('HELP_CENTER.UPGRADE_PAGE.TITLE') }}
            </h1>
            <p
              class="max-w-2xl text-base font-normal leading-6 text-left sm:text-center text-n-slate-11"
            >
              {{
                isOnChatwootCloud
                  ? $t('HELP_CENTER.UPGRADE_PAGE.DESCRIPTION')
                  : $t('HELP_CENTER.UPGRADE_PAGE.SELF_HOSTED_DESCRIPTION')
              }}
            </p>
          </div>
          <div
            v-if="isOnChatwootCloud"
            class="flex flex-row gap-3 justify-start items-center sm:justify-center"
          >
            <NextButton
              outline
              :label="$t('HELP_CENTER.UPGRADE_PAGE.BUTTON.LEARN_MORE')"
              @click="openHelpCenterDocs"
            />
            <NextButton
              :label="$t('HELP_CENTER.UPGRADE_PAGE.BUTTON.UPGRADE')"
              @click="openBillingPage"
            />
          </div>
        </div>
        <div
          class="grid grid-cols-1 sm:grid-cols-2 gap-6 sm:gap-16 w-full max-w-2xl overflow-auto"
        >
          <div
            v-for="feature in upgradeFeature"
            :key="feature.key"
            class="w-64 min-w-full"
          >
            <div class="flex gap-2 flex-row">
              <div>
                <fluent-icon
                  :icon="feature.icon"
                  icon-lib="lucide"
                  :size="26"
                  class="mt-px text-n-slate-12"
                />
              </div>
              <div>
                <h5 class="font-semibold text-lg text-n-slate-12">
                  {{ feature.title }}
                </h5>
                <p class="text-sm leading-6 text-n-slate-12">
                  {{ feature.description }}
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>
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
