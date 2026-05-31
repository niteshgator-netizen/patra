<script setup>
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter, useRoute } from 'vue-router';
import { parseBoolean } from '@chatwoot/utils';
import mfaAPI from 'dashboard/api/mfa';
import { useAlert } from 'dashboard/composables';
import MfaStatusCard from './MfaStatusCard.vue';
import MfaSetupWizard from './MfaSetupWizard.vue';
import MfaManagementActions from './MfaManagementActions.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';

const { t } = useI18n();
const router = useRouter();
const route = useRoute();

// State
const mfaEnabled = ref(false);
const backupCodesGenerated = ref(false);
const showSetup = ref(false);
const provisioningUri = ref('');
const qrCodeUrl = ref('');
const secretKey = ref('');
const backupCodes = ref([]);

// Component refs
const setupWizardRef = ref(null);
const managementActionsRef = ref(null);

// Load MFA status on mount
onMounted(async () => {
  // Check if MFA is enabled globally
  if (!parseBoolean(window.chatwootConfig?.isMfaEnabled)) {
    // Redirect to profile settings if MFA is disabled
    router.push({
      name: 'profile_settings_index',
      params: {
        accountId: route.params.accountId,
      },
    });
    return;
  }

  try {
    const response = await mfaAPI.get();
    mfaEnabled.value = response.data.enabled;
    backupCodesGenerated.value = response.data.backup_codes_generated;
  } catch (error) {
    // Handle error silently
  }
});

// Start MFA setup
const startMfaSetup = async () => {
  try {
    const response = await mfaAPI.enable();

    // Store the provisioning URI
    provisioningUri.value =
      response.data.provisioning_uri || response.data.provisioning_url;

    // Store QR code URL if provided by backend
    if (response.data.qr_code_url) {
      qrCodeUrl.value = response.data.qr_code_url;
    }

    secretKey.value = response.data.secret;
    // Backup codes are now generated after verification, not during enable
    backupCodes.value = [];
    showSetup.value = true;
  } catch (error) {
    useAlert(t('MFA_SETTINGS.SETUP.ERROR_STARTING'));
  }
};

// Verify OTP code
const verifyCode = async verificationCode => {
  try {
    const response = await mfaAPI.verify(verificationCode);
    // Store backup codes returned from verification
    if (response.data.backup_codes) {
      backupCodes.value = response.data.backup_codes;
    }
    return true;
  } catch (error) {
    setupWizardRef.value?.handleVerificationError(
      error.response?.data?.error || t('MFA_SETTINGS.SETUP.INVALID_CODE')
    );
    throw error;
  }
};

// Complete MFA setup
const completeMfaSetup = () => {
  mfaEnabled.value = true;
  backupCodesGenerated.value = true;
  showSetup.value = false;
  useAlert(t('MFA_SETTINGS.SETUP.SUCCESS'));
};

// Cancel setup
const cancelSetup = () => {
  showSetup.value = false;
};

// Disable MFA
const disableMfa = async ({ password, otpCode, backupCode }) => {
  try {
    await mfaAPI.disable(password, { otpCode, backupCode });
    mfaEnabled.value = false;
    backupCodesGenerated.value = false;
    managementActionsRef.value?.resetDisableForm();
    useAlert(t('MFA_SETTINGS.DISABLE.SUCCESS'));
  } catch (error) {
    useAlert(t('MFA_SETTINGS.DISABLE.ERROR'));
  }
};

// Regenerate backup codes
const regenerateBackupCodes = async ({ otpCode }) => {
  try {
    const response = await mfaAPI.regenerateBackupCodes(otpCode);
    backupCodes.value = response.data.backup_codes;
    managementActionsRef.value?.resetRegenerateForm();
    managementActionsRef.value?.showBackupCodesDialog();
    useAlert(t('MFA_SETTINGS.REGENERATE.SUCCESS'));
  } catch (error) {
    useAlert(t('MFA_SETTINGS.REGENERATE.ERROR'));
  }
};
</script>

<template>
  <div class="pat-page-wrap">
    <div class="pat-page-main">
      <div class="grid w-full">
        <BaseSettingsHeader
          :title="$t('MFA_SETTINGS.TITLE')"
          :description="$t('MFA_SETTINGS.SUBTITLE')"
          :back-button-label="$t('PROFILE_SETTINGS.TITLE')"
        />

        <div class="grid gap-4 w-full mt-4">
          <!-- MFA Status Card -->
          <MfaStatusCard
            :mfa-enabled="mfaEnabled"
            :show-setup="showSetup"
            @enable-mfa="startMfaSetup"
          />

          <!-- MFA Setup Wizard -->
          <MfaSetupWizard
            ref="setupWizardRef"
            :show-setup="showSetup"
            :mfa-enabled="mfaEnabled"
            :provisioning-uri="provisioningUri"
            :secret-key="secretKey"
            :backup-codes="backupCodes"
            :qr-code-url-prop="qrCodeUrl"
            @cancel="cancelSetup"
            @verify="verifyCode"
            @complete="completeMfaSetup"
          />

          <!-- MFA Management Actions -->
          <MfaManagementActions
            ref="managementActionsRef"
            :mfa-enabled="mfaEnabled"
            :backup-codes="backupCodes"
            @disable-mfa="disableMfa"
            @regenerate-backup-codes="regenerateBackupCodes"
          />
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
