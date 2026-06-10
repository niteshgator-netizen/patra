<script>
/* eslint-env browser */
/* global FB */
import { useVuelidate } from '@vuelidate/core';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { required } from '@vuelidate/validators';
import LoadingState from 'dashboard/components/widgets/LoadingState.vue';

import ChannelApi from '../../../../../api/channels';
import PageHeader from '../../SettingsSubPageHeader.vue';
import router from '../../../../index';
import { useBranding } from 'shared/composables/useBranding';
import NextButton from 'dashboard/components-next/button/Button.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';

import { loadScript } from 'dashboard/helper/DOMHelpers';
import * as Sentry from '@sentry/vue';

export default {
  components: {
    LoadingState,
    PageHeader,
    NextButton,
    ComboBox,
  },
  setup() {
    const { accountId } = useAccount();
    const { replaceInstallationName } = useBranding();
    return {
      accountId,
      replaceInstallationName,
      v$: useVuelidate(),
    };
  },
  data() {
    return {
      isCreating: false,
      hasError: false,
      omniauth_token: '',
      user_access_token: '',
      channel: 'facebook',
      selectedPage: { name: null, id: null },
      pageName: '',
      pageList: [],
      emptyStateMessage: this.$t('INBOX_MGMT.DETAILS.LOADING_FB'),
      errorStateMessage: '',
      errorStateDescription: '',
      hasLoginStarted: false,
    };
  },

  validations: {
    pageName: {
      required,
    },

    selectedPage: {
      isEmpty() {
        return this.selectedPage !== null && !!this.selectedPage.name;
      },
    },
  },

  computed: {
    showLoader() {
      return !this.user_access_token || this.isCreating;
    },
    getSelectablePages() {
      return this.pageList.filter(item => !item.exists);
    },
    comboBoxPageOptions() {
      return this.getSelectablePages.map(({ id, name }) => ({
        value: id,
        label: name,
      }));
    },
  },

  mounted() {
    window.fbAsyncInit = this.runFBInit;
  },

  methods: {
    async startLogin() {
      this.hasLoginStarted = true;
      try {
        // this will load the SDK in a promise, and resolve it when the sdk is loaded
        // in case the SDK is already present, it will resolve immediately
        await this.loadFBsdk();
        this.runFBInit(); // run init anyway, `tryFBlogin` won't wait for `fbAsyncInit` otherwise.
        this.tryFBlogin(); // make an attempt to login
      } catch (error) {
        if (error.name === 'ScriptLoaderError') {
          // if the error was related to script loading, we show a toast
          useAlert(this.$t('INBOX_MGMT.DETAILS.ERROR_FB_LOADING'));
        } else {
          // if the error was anything else, we capture it and show a toast
          Sentry.captureException(error);
          useAlert(this.$t('INBOX_MGMT.DETAILS.ERROR_FB_AUTH'));
        }
      }
    },

    setPageName(pageId) {
      const page = this.pageList.find(p => p.id === pageId);
      if (page) {
        this.selectedPage = page;
        this.pageName = page.name;
      } else {
        this.selectedPage = { name: null, id: null };
        this.pageName = '';
      }
      this.v$.selectedPage.$touch();
    },

    initChannelAuth(channel) {
      if (channel === 'facebook') {
        this.loadFBsdk();
      }
    },

    runFBInit() {
      FB.init({
        appId: window.chatwootConfig.fbAppId,
        xfbml: true,
        version: window.chatwootConfig.fbApiVersion,
        status: true,
      });
      window.fbSDKLoaded = true;
      FB.AppEvents.logPageView();
    },

    async loadFBsdk() {
      return loadScript('https://connect.facebook.net/en_US/sdk.js', {
        id: 'facebook-jssdk',
      });
    },

    tryFBlogin() {
      FB.login(
        response => {
          this.hasError = false;
          if (response.status === 'connected') {
            this.fetchPages(response.authResponse.accessToken);
          } else if (response.status === 'not_authorized') {
            // eslint-disable-next-line no-console
            console.error('FACEBOOK AUTH ERROR', response);
            this.hasError = true;
            // The person is logged into Facebook, but not your app.
            this.errorStateMessage = this.$t(
              'INBOX_MGMT.DETAILS.ERROR_FB_UNAUTHORIZED'
            );
            this.errorStateDescription = this.$t(
              'INBOX_MGMT.DETAILS.ERROR_FB_UNAUTHORIZED_HELP'
            );
          } else {
            // eslint-disable-next-line no-console
            console.error('FACEBOOK AUTH ERROR', response);
            this.hasError = true;
            // The person is not logged into Facebook, so we're not sure if
            // they are logged into this app or not.
            this.errorStateMessage = this.$t(
              'INBOX_MGMT.DETAILS.ERROR_FB_AUTH'
            );
            this.errorStateDescription = '';
          }
        },
        {
          scope:
            'pages_manage_metadata,business_management,pages_messaging,instagram_basic,pages_show_list,pages_read_engagement,instagram_manage_messages',
        }
      );
    },

    async fetchPages(_token) {
      try {
        const response = await ChannelApi.fetchFacebookPages(
          _token,
          this.accountId
        );
        const {
          data: { data },
        } = response;
        this.pageList = data.page_details;
        this.user_access_token = data.user_access_token;
      } catch (error) {
        // Ignore error
      }
    },

    channelParams() {
      return {
        user_access_token: this.user_access_token,
        page_access_token: this.selectedPage.access_token,
        page_id: this.selectedPage.id,
        inbox_name: this.selectedPage.name?.trim(),
      };
    },

    createChannel() {
      this.v$.$touch();
      if (!this.v$.$error) {
        this.emptyStateMessage = this.$t('INBOX_MGMT.DETAILS.CREATING_CHANNEL');
        this.isCreating = true;
        this.$store
          .dispatch('inboxes/createFBChannel', this.channelParams())
          .then(data => {
            router.replace({
              name: 'settings_inboxes_add_agents',
              params: { page: 'new', inbox_id: data.id },
            });
          })
          .catch(() => {
            this.isCreating = false;
          });
      }
    },
  },
};
</script>

<template>
  <div class="w-full h-full col-span-6 p-6 overflow-auto">
    <div
      v-if="!hasLoginStarted"
      class="flex flex-col items-center justify-center h-full text-center"
    >
      <div class="pat-connect-card">
        <div class="pat-connect-ic">f</div>
        <h3 class="pat-connect-title">
          {{ $t('INBOX_MGMT.ADD.FB.CONNECT_TITLE') }}
        </h3>
        <p class="pat-connect-desc">
          {{ $t('INBOX_MGMT.ADD.FB.CONNECT_DESC') }}
        </p>
        <button type="button" class="pat-connect-cta" @click="startLogin()">
          {{ $t('INBOX_MGMT.ADD.FB.CONTINUE_WITH_FACEBOOK') }}
        </button>
        <div class="pat-connect-note">
          {{ $t('INBOX_MGMT.ADD.FB.SECURITY_NOTE') }}
        </div>
        <p class="pat-connect-help">
          {{ replaceInstallationName($t('INBOX_MGMT.ADD.FB.HELP')) }}
        </p>
      </div>
    </div>
    <div v-else>
      <div v-if="hasError" class="max-w-lg mx-auto text-center">
        <h5>{{ errorStateMessage }}</h5>
        <p
          v-if="errorStateDescription"
          v-dompurify-html="errorStateDescription"
        />
      </div>
      <LoadingState v-else-if="showLoader" :message="emptyStateMessage" />
      <form
        v-else
        class="flex flex-col flex-wrap mx-0"
        @submit.prevent="createChannel()"
      >
        <div class="w-full">
          <PageHeader
            :header-title="$t('INBOX_MGMT.ADD.DETAILS.TITLE')"
            :header-content="
              replaceInstallationName($t('INBOX_MGMT.ADD.DETAILS.DESC'))
            "
          />
        </div>
        <div class="w-3/5">
          <div class="w-full mb-2">
            <div class="input-wrap" :class="{ error: v$.selectedPage.$error }">
              <span class="text-n-slate-12 text-start">
                {{ $t('INBOX_MGMT.ADD.FB.CHOOSE_PAGE') }}
              </span>
              <ComboBox
                :model-value="selectedPage.id"
                :options="comboBoxPageOptions"
                :placeholder="$t('INBOX_MGMT.ADD.FB.PICK_A_VALUE')"
                :has-error="v$.selectedPage.$error"
                class="[&>div>button]:!bg-n-alpha-black2 mt-1"
                @update:model-value="setPageName"
              />
              <span v-if="v$.selectedPage.$error" class="message mt-0.5">
                {{ $t('INBOX_MGMT.ADD.FB.CHOOSE_PLACEHOLDER') }}
              </span>
            </div>
          </div>
          <div class="w-full">
            <label :class="{ error: v$.pageName.$error }">
              {{ $t('INBOX_MGMT.ADD.FB.INBOX_NAME') }}
              <input
                v-model="pageName"
                type="text"
                :placeholder="$t('INBOX_MGMT.ADD.FB.PICK_NAME')"
                @input="v$.pageName.$touch"
              />
              <span v-if="v$.pageName.$error" class="message">
                {{ $t('INBOX_MGMT.ADD.FB.ADD_NAME') }}
              </span>
            </label>
          </div>
          <div class="w-full text-right">
            <NextButton :label="$t('INBOX_MGMT.ADD.FB.CREATE_INBOX')" />
          </div>
        </div>
      </form>
    </div>
  </div>
</template>

<style scoped>
/* B4: spec "Connect Facebook" card (PATRA_APP_final.html connect-fb screen) —
   centered card, brand icon tile, CTA, reassurance line. Token-driven, both
   themes. This card is the template for the other channel connect screens. */
.pat-connect-card {
  max-width: 500px;
  width: 100%;
  margin: 0 auto;
  padding: 36px 28px;
  border-radius: 16px;
  border: 1px solid var(--border, #e5e3eb);
  background: var(--surface, #fff);
  display: flex;
  flex-direction: column;
  align-items: center;
}

.pat-connect-ic {
  width: 64px;
  height: 64px;
  border-radius: 18px;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 36px;
  font-weight: 700;
  font-family: 'Space Grotesk', sans-serif;
  color: #fff;
  background: linear-gradient(135deg, #1877f2, #0d5cbf);
  margin-bottom: 16px;
}

.pat-connect-title {
  font-family: 'Space Grotesk', sans-serif;
  font-weight: 600;
  font-size: 18px;
  color: var(--text, #1a1a24);
  margin-bottom: 8px;
}

.pat-connect-desc {
  font-size: 13px;
  color: var(--text-2, #4a4756);
  line-height: 1.55;
  margin-bottom: 18px;
  max-width: 380px;
}

.pat-connect-cta {
  padding: 10px 22px;
  border-radius: 10px;
  border: none;
  font-size: 13.5px;
  font-weight: 600;
  color: #fff;
  background: linear-gradient(135deg, #1877f2, #0d5cbf);
  cursor: pointer;
  transition: all 0.22s cubic-bezier(0.34, 1.56, 0.64, 1);
}

.pat-connect-cta:hover {
  transform: translateY(-2px);
  box-shadow: 0 8px 22px rgba(24, 119, 242, 0.35);
}

.pat-connect-note {
  margin-top: 14px;
  font-size: 12px;
  color: var(--text-4, #908da0);
}

.pat-connect-help {
  margin-top: 14px;
  font-size: 12px;
  color: var(--text-3, #75727f);
  max-width: 380px;
  line-height: 1.5;
}
</style>
