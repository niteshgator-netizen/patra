<script setup>
import { computed } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useI18n } from 'vue-i18n';
import { useToggle } from '@vueuse/core';
import { useAlert } from 'dashboard/composables';
import WootConfirmDeleteModal from 'dashboard/components/widgets/modal/ConfirmDeleteModal.vue';

const { t } = useI18n();
const store = useStore();
const uiFlags = useMapGetter('accounts/getUIFlags');
const { currentAccount } = useAccount();
const [showDeletePopup, toggleDeletePopup] = useToggle();

const confirmPlaceHolderText = computed(() => {
  return `${t('GENERAL_SETTINGS.ACCOUNT_DELETE_SECTION.CONFIRM.PLACE_HOLDER', {
    accountName: currentAccount.value.name,
  })}`;
});

const isMarkedForDeletion = computed(() => {
  const { custom_attributes = {} } = currentAccount.value;
  return !!custom_attributes.marked_for_deletion_at;
});

const markedForDeletionDate = computed(() => {
  const { custom_attributes = {} } = currentAccount.value;
  if (!custom_attributes.marked_for_deletion_at) return null;
  return new Date(custom_attributes.marked_for_deletion_at);
});

const markedForDeletionReason = computed(() => {
  const { custom_attributes = {} } = currentAccount.value;
  return custom_attributes.marked_for_deletion_reason || 'manual_deletion';
});

const formattedDeletionDate = computed(() => {
  if (!markedForDeletionDate.value) return '';
  return markedForDeletionDate.value.toLocaleString();
});

const markedForDeletionMessage = computed(() => {
  const params = { deletionDate: formattedDeletionDate.value };

  if (markedForDeletionReason.value === 'manual_deletion') {
    return t(
      `GENERAL_SETTINGS.ACCOUNT_DELETE_SECTION.SCHEDULED_DELETION.MESSAGE_MANUAL`,
      params
    );
  }

  return t(
    `GENERAL_SETTINGS.ACCOUNT_DELETE_SECTION.SCHEDULED_DELETION.MESSAGE_INACTIVITY`,
    params
  );
});

function handleDeletionError(error) {
  const message = error.response?.data?.message;
  if (message) {
    useAlert(message);
    return;
  }
  useAlert(t('GENERAL_SETTINGS.ACCOUNT_DELETE_SECTION.FAILURE'));
}

async function markAccountForDeletion() {
  toggleDeletePopup(false);
  try {
    await store.dispatch('accounts/toggleDeletion', {
      action_type: 'delete',
    });
    await store.dispatch('accounts/get');
    useAlert(t('GENERAL_SETTINGS.ACCOUNT_DELETE_SECTION.SUCCESS'));
  } catch (error) {
    handleDeletionError(error);
  }
}

async function clearDeletionMark() {
  try {
    await store.dispatch('accounts/toggleDeletion', {
      action_type: 'undelete',
    });

    await store.dispatch('accounts/get');
    useAlert(t('GENERAL_SETTINGS.UPDATE.SUCCESS'));
  } catch (error) {
    useAlert(t('GENERAL_SETTINGS.UPDATE.ERROR'));
  }
}
</script>

<template>
  <div class="card">
    <div class="card-t display">
      <span class="dot" />
      {{ t('GENERAL_SETTINGS.ACCOUNT_DELETE_SECTION.TITLE') }}
    </div>
    <p class="delete-note">
      {{ t('GENERAL_SETTINGS.ACCOUNT_DELETE_SECTION.NOTE') }}
    </p>

    <div v-if="isMarkedForDeletion" class="delete-scheduled">
      <p class="delete-msg">{{ markedForDeletionMessage }}</p>
      <button
        type="button"
        class="btn danger"
        :disabled="uiFlags.isUpdating"
        @click="clearDeletionMark"
      >
        {{
          uiFlags.isUpdating
            ? $t('PATRA.SETTINGS.SAVING')
            : $t(
                'GENERAL_SETTINGS.ACCOUNT_DELETE_SECTION.SCHEDULED_DELETION.CLEAR_BUTTON'
              )
        }}
      </button>
    </div>

    <button
      v-if="!isMarkedForDeletion"
      type="button"
      class="btn danger"
      @click="toggleDeletePopup(true)"
    >
      {{ $t('GENERAL_SETTINGS.ACCOUNT_DELETE_SECTION.BUTTON_TEXT') }}
    </button>
  </div>

  <WootConfirmDeleteModal
    v-if="showDeletePopup"
    v-model:show="showDeletePopup"
    :title="$t('GENERAL_SETTINGS.ACCOUNT_DELETE_SECTION.CONFIRM.TITLE')"
    :message="$t('GENERAL_SETTINGS.ACCOUNT_DELETE_SECTION.CONFIRM.MESSAGE')"
    :confirm-text="
      $t('GENERAL_SETTINGS.ACCOUNT_DELETE_SECTION.CONFIRM.BUTTON_TEXT')
    "
    :reject-text="$t('GENERAL_SETTINGS.ACCOUNT_DELETE_SECTION.CONFIRM.DISMISS')"
    :confirm-value="currentAccount.name"
    :confirm-place-holder-text="confirmPlaceHolderText"
    @on-confirm="markAccountForDeletion"
    @on-close="toggleDeletePopup(false)"
  />
</template>

<style scoped>
.display {
  font-family: 'Space Grotesk', sans-serif;
}

.card {
  background: var(--surface, #0c0b12);
  border: 1px solid var(--border, #171520);
  border-radius: 16px;
  padding: 22px;
  margin-bottom: 16px;
}

.card-t {
  font-weight: 600;
  font-size: 15px;
  display: flex;
  align-items: center;
  gap: 8px;
  margin-bottom: 18px;
}

.card-t .dot {
  width: 7px;
  height: 7px;
  border-radius: 50%;
  background: var(--patra-2, #8b5cf6);
  box-shadow: 0 0 8px var(--patra-glow, rgba(110, 86, 207, 0.55));
}

.delete-note {
  font-size: 12.5px;
  color: var(--text-3, #75727f);
  margin: -6px 0 14px;
}

.delete-scheduled {
  background: rgba(248, 81, 73, 0.1);
  border: 1px solid rgba(248, 81, 73, 0.3);
  border-radius: 10px;
  padding: 14px;
}

.delete-msg {
  font-size: 13px;
  color: var(--text-2, #a8a6b6);
  margin: 0 0 12px;
}

.btn {
  font-size: 13px;
  font-weight: 600;
  padding: 10px 18px;
  border-radius: 10px;
  border: 1px solid var(--border-hi, #2e2940);
  background: var(--surface-2, #131119);
  color: var(--text, #ededf2);
  cursor: pointer;
  transition: all 0.22s cubic-bezier(0.34, 1.56, 0.64, 1);
}

.btn:hover:not(:disabled) {
  transform: translateY(-2px);
  box-shadow: 0 6px 16px rgba(0, 0, 0, 0.3);
}

.btn:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}

.btn.danger {
  background: rgba(248, 81, 73, 0.16);
  border-color: rgba(248, 81, 73, 0.4);
  color: #f85149;
}

.btn.danger:hover:not(:disabled) {
  background: #f85149;
  color: #fff;
}
</style>
