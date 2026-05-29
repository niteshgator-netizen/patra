<script>
export default {
  methods: {
    getGoogleAuthUrl() {
      // Ideally a request to /auth/google_oauth2 should be made
      // Creating the URL manually because the devise-token-auth with
      // omniauth has a standing issue on redirecting the post request
      // https://github.com/lynndylanhurley/devise_token_auth/issues/1466
      const baseUrl = 'https://accounts.google.com/o/oauth2/auth';
      const clientId = window.chatwootConfig.googleOAuthClientId;
      const redirectUri = window.chatwootConfig.googleOAuthCallbackUrl;
      const responseType = 'code';
      const scope = 'email profile';

      // Build the query string
      const queryString = new URLSearchParams({
        client_id: clientId,
        redirect_uri: redirectUri,
        response_type: responseType,
        scope: scope,
      }).toString();

      // Construct the full URL
      return `${baseUrl}?${queryString}`;
    },
  },
};
</script>

<!-- eslint-disable vue/no-unused-refs -->
<!-- Added ref for writing specs -->
<template>
  <div class="flex flex-col">
    <a
      :href="getGoogleAuthUrl()"
      class="w-full bg-auth-surface-2 text-auth-text border border-auth-border rounded-xl px-3.5 py-3 cursor-pointer text-sm font-medium flex items-center justify-center gap-2.5 transition-all hover:bg-auth-surface-3 hover:border-auth-border-hi hover:-translate-y-px no-underline"
    >
      <span class="i-logos-google-icon h-6" />
      <span>
        <slot>{{ $t('LOGIN.OAUTH.GOOGLE_LOGIN') }}</slot>
      </span>
    </a>
  </div>
</template>
