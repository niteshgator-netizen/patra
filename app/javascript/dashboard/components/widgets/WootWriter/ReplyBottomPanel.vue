<script>
import { ref } from 'vue';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useAlert } from 'dashboard/composables';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import FileUpload from 'vue-upload-component';
import * as ActiveStorage from 'activestorage';
import inboxMixin from 'shared/mixins/inboxMixin';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { getAllowedFileTypesByChannel } from '@chatwoot/utils';
import { ALLOWED_FILE_TYPES } from 'shared/constants/messages';
import VideoCallButton from '../VideoCallButton.vue';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import { mapGetters } from 'vuex';
import NextButton from 'dashboard/components-next/button/Button.vue';
import ScheduleMessagePopover from '../conversation/ScheduleMessagePopover.vue';

export default {
  name: 'ReplyBottomPanel',
  components: {
    NextButton,
    FileUpload,
    VideoCallButton,
    ScheduleMessagePopover,
  },
  mixins: [inboxMixin],
  props: {
    isNote: {
      type: Boolean,
      default: false,
    },
    onSend: {
      type: Function,
      default: () => {},
    },
    sendButtonText: {
      type: String,
      default: '',
    },
    recordingAudioDurationText: {
      type: String,
      default: '00:00',
    },
    // inbox prop is used in /mixins/inboxMixin,
    // remove this props when refactoring to composable if not needed
    // eslint-disable-next-line vue/no-unused-properties
    inbox: {
      type: Object,
      default: () => ({}),
    },
    showFileUpload: {
      type: Boolean,
      default: false,
    },
    showAudioRecorder: {
      type: Boolean,
      default: false,
    },
    onFileUpload: {
      type: Function,
      default: () => {},
    },
    toggleEmojiPicker: {
      type: Function,
      default: () => {},
    },
    toggleAudioRecorder: {
      type: Function,
      default: () => {},
    },
    toggleAudioRecorderPlayPause: {
      type: Function,
      default: () => {},
    },
    isRecordingAudio: {
      type: Boolean,
      default: false,
    },
    recordingAudioState: {
      type: String,
      default: '',
    },
    isSendDisabled: {
      type: Boolean,
      default: false,
    },
    isOnPrivateNote: {
      type: Boolean,
      default: false,
    },
    enableMultipleFileUpload: {
      type: Boolean,
      default: true,
    },
    enableWhatsAppTemplates: {
      type: Boolean,
      default: false,
    },
    enableContentTemplates: {
      type: Boolean,
      default: false,
    },
    conversationId: {
      type: Number,
      required: true,
    },
    // eslint-disable-next-line vue/no-unused-properties
    message: {
      type: String,
      default: '',
    },
    newConversationModalActive: {
      type: Boolean,
      default: false,
    },
    portalSlug: {
      type: String,
      required: true,
    },
    conversationType: {
      type: String,
      default: '',
    },
    showQuotedReplyToggle: {
      type: Boolean,
      default: false,
    },
    quotedReplyEnabled: {
      type: Boolean,
      default: false,
    },
    isEditorDisabled: {
      type: Boolean,
      default: false,
    },
  },
  emits: [
    'toggleInsertArticle',
    'selectWhatsappTemplate',
    'selectContentTemplate',
    'toggleQuotedReply',
    'messageScheduled',
  ],
  setup(props) {
    const { setSignatureFlagForInbox, fetchSignatureFlagFromUISettings } =
      useUISettings();

    const uploadRef = ref(false);

    const keyboardEvents = {
      '$mod+Alt+KeyA': {
        action: () => {
          // Skip if editor is disabled (e.g., WhatsApp 24-hour window expired)
          if (props.isEditorDisabled) return;

          // TODO: This is really hacky, we need to replace the file picker component with
          // a custom one, where the logic and the component markup is isolated.
          // Once we have the custom component, we can remove the hacky logic below.

          const uploadTriggerButton = document.querySelector(
            '#conversationAttachment'
          );
          if (uploadTriggerButton) uploadTriggerButton.click();
        },
        allowOnFocusedInput: true,
      },
    };

    useKeyboardEvents(keyboardEvents);

    return {
      setSignatureFlagForInbox,
      fetchSignatureFlagFromUISettings,
      uploadRef,
    };
  },
  data() {
    return {
      ALLOWED_FILE_TYPES,
      showSchedulePopover: false,
    };
  },
  computed: {
    ...mapGetters({
      accountId: 'getCurrentAccountId',
      isFeatureEnabledonAccount: 'accounts/isFeatureEnabledonAccount',
      uiFlags: 'integrations/getUIFlags',
    }),
    wrapClass() {
      return {
        'is-note-mode': this.isNote,
      };
    },
    showAttachButton() {
      if (this.isEditorDisabled) return false;
      return this.showFileUpload || this.isNote;
    },
    showAudioRecorderButton() {
      if (this.isEditorDisabled) return false;
      if (this.isALineChannel || this.isATiktokChannel) {
        return false;
      }
      // Disable audio recorder for safari browser as recording is not supported
      // const isSafari = /^((?!chrome|android|crios|fxios).)*safari/i.test(
      //   navigator.userAgent
      // );

      return (
        this.isFeatureEnabledonAccount(
          this.accountId,
          FEATURE_FLAGS.VOICE_RECORDER
        ) && this.showAudioRecorder
        // !isSafari
      );
    },
    showAudioPlayStopButton() {
      if (this.isEditorDisabled) return false;
      return this.showAudioRecorder && this.isRecordingAudio;
    },
    isInstagramDM() {
      return this.conversationType === 'instagram_direct_message';
    },
    allowedFileTypes() {
      // Use default file types for private notes
      if (this.isOnPrivateNote) {
        return this.ALLOWED_FILE_TYPES;
      }

      let channelType = this.channelType || this.inbox?.channel_type;

      if (this.isAnInstagramChannel || this.isInstagramDM) {
        channelType = INBOX_TYPES.INSTAGRAM;
      }

      return getAllowedFileTypesByChannel({
        channelType,
        medium: this.inbox?.medium,
      });
    },
    enableDragAndDrop() {
      return !this.newConversationModalActive;
    },
    audioRecorderPlayStopIcon() {
      switch (this.recordingAudioState) {
        // playing paused recording stopped inactive destroyed
        case 'playing':
          return 'i-ph-pause';
        case 'paused':
          return 'i-ph-play';
        case 'stopped':
          return 'i-ph-play';
        default:
          return 'i-ph-stop';
      }
    },
    showMessageSignatureButton() {
      if (this.isEditorDisabled) return false;
      return !this.isOnPrivateNote;
    },
    sendWithSignature() {
      // channelType is sourced from inboxMixin
      return this.fetchSignatureFlagFromUISettings(this.channelType);
    },
    signatureToggleTooltip() {
      return this.sendWithSignature
        ? this.$t('CONVERSATION.FOOTER.DISABLE_SIGN_TOOLTIP')
        : this.$t('CONVERSATION.FOOTER.ENABLE_SIGN_TOOLTIP');
    },
    enableInsertArticleInReply() {
      return this.portalSlug;
    },
    isFetchingAppIntegrations() {
      return this.uiFlags.isFetching;
    },
    quotedReplyToggleTooltip() {
      return this.quotedReplyEnabled
        ? this.$t('CONVERSATION.REPLYBOX.QUOTED_REPLY.DISABLE_TOOLTIP')
        : this.$t('CONVERSATION.REPLYBOX.QUOTED_REPLY.ENABLE_TOOLTIP');
    },
  },
  mounted() {
    ActiveStorage.start();
  },
  methods: {
    toggleMessageSignature() {
      this.setSignatureFlagForInbox(this.channelType, !this.sendWithSignature);
    },
    toggleInsertArticle() {
      this.$emit('toggleInsertArticle');
    },
    sendLater() {
      if (!this.message.trim()) {
        useAlert(this.$t('PATRA.SCHEDULED.EMPTY_MESSAGE'));
        return;
      }
      this.showSchedulePopover = true;
    },
    closeSchedulePopover() {
      this.showSchedulePopover = false;
    },
    onMessageScheduled() {
      this.$emit('messageScheduled');
    },
  },
};
</script>

<template>
  <div class="patra-composer-bar flex justify-between" :class="wrapClass">
    <div class="patra-composer-tools left-wrap">
      <NextButton
        v-if="!isEditorDisabled"
        v-tooltip.top-end="$t('CONVERSATION.REPLYBOX.TIP_EMOJI_ICON')"
        icon="i-ph-smiley-sticker"
        slate
        faded
        sm
        @click="toggleEmojiPicker"
      />
      <FileUpload
        v-if="showAttachButton"
        ref="uploadRef"
        v-tooltip.top-end="$t('CONVERSATION.REPLYBOX.TIP_ATTACH_ICON')"
        input-id="conversationAttachment"
        :size="4096 * 4096"
        :accept="allowedFileTypes"
        :multiple="enableMultipleFileUpload"
        :drop="enableDragAndDrop"
        :drop-directory="false"
        :data="{
          direct_upload_url: '/rails/active_storage/direct_uploads',
          direct_upload: true,
        }"
        @input-file="onFileUpload"
      >
        <NextButton
          v-if="showAttachButton"
          v-tooltip.top-end="$t('CONVERSATION.REPLYBOX.TIP_ATTACH_ICON')"
          icon="i-ph-paperclip"
          slate
          faded
          sm
        />
      </FileUpload>
      <NextButton
        v-if="showAudioRecorderButton"
        v-tooltip.top-end="$t('CONVERSATION.REPLYBOX.TIP_AUDIORECORDER_ICON')"
        :icon="!isRecordingAudio ? 'i-ph-microphone' : 'i-ph-microphone-slash'"
        slate
        faded
        sm
        @click="toggleAudioRecorder"
      />
      <NextButton
        v-if="showAudioPlayStopButton"
        :icon="audioRecorderPlayStopIcon"
        slate
        faded
        sm
        :label="recordingAudioDurationText"
        @click="toggleAudioRecorderPlayPause"
      />
      <NextButton
        v-if="showMessageSignatureButton"
        v-tooltip.top-end="signatureToggleTooltip"
        icon="i-ph-signature"
        slate
        faded
        sm
        @click="toggleMessageSignature"
      />
      <NextButton
        v-if="showQuotedReplyToggle"
        v-tooltip.top-end="quotedReplyToggleTooltip"
        icon="i-ph-quotes"
        :variant="quotedReplyEnabled ? 'solid' : 'faded'"
        color="slate"
        sm
        :aria-pressed="quotedReplyEnabled"
        @click="$emit('toggleQuotedReply')"
      />
      <NextButton
        v-if="enableWhatsAppTemplates"
        v-tooltip.top-end="$t('CONVERSATION.FOOTER.WHATSAPP_TEMPLATES')"
        icon="i-ph-whatsapp-logo"
        slate
        faded
        sm
        @click="$emit('selectWhatsappTemplate')"
      />
      <NextButton
        v-if="enableContentTemplates"
        v-tooltip.top-end="'Content Templates'"
        icon="i-ph-whatsapp-logo"
        slate
        faded
        sm
        @click="$emit('selectContentTemplate')"
      />
      <VideoCallButton
        v-if="
          (isAWebWidgetInbox || isAPIInbox) &&
          !isOnPrivateNote &&
          !isEditorDisabled
        "
        :conversation-id="conversationId"
      />
      <transition name="modal-fade">
        <div
          v-show="uploadRef && uploadRef.dropActive"
          class="flex fixed top-0 right-0 bottom-0 left-0 z-20 flex-col gap-2 justify-center items-center w-full h-full text-n-slate-12 bg-modal-backdrop-light dark:bg-modal-backdrop-dark"
        >
          <fluent-icon icon="cloud-backup" size="40" />
          <h4 class="text-2xl break-words text-n-slate-12">
            {{ $t('CONVERSATION.REPLYBOX.DRAG_DROP') }}
          </h4>
        </div>
      </transition>
      <NextButton
        v-if="enableInsertArticleInReply"
        v-tooltip.top-end="$t('HELP_CENTER.ARTICLE_SEARCH.OPEN_ARTICLE_SEARCH')"
        icon="i-ph-article-ny-times"
        slate
        faded
        sm
        @click="toggleInsertArticle"
      />
    </div>
    <div class="patra-composer-right right-wrap relative">
      <ScheduleMessagePopover
        :show="showSchedulePopover"
        :conversation-id="conversationId"
        :message="message"
        @close="closeSchedulePopover"
        @scheduled="onMessageScheduled"
      />
      <NextButton
        v-if="!isNote && !isEditorDisabled"
        v-tooltip.top-end="$t('PATRA.SCHEDULED.SEND_LATER')"
        icon="i-lucide-clock"
        slate
        faded
        sm
        @click="sendLater"
      />
      <NextButton
        :label="sendButtonText"
        type="submit"
        sm
        :color="isNote ? 'amber' : 'blue'"
        :disabled="isSendDisabled"
        class="patra-composer-send flex-shrink-0"
        @click="onSend"
      />
    </div>
  </div>
</template>

<style scoped>
.patra-composer-bar {
  --pb-surface-2: #131119;
  --pb-surface-3: #1b1925;
  --pb-border: #171520;
  --pb-text-2: #a8a6b6;
  --pb-text-3: #75727f;
  --pb-text-4: #54515e;
  --pb-patra: #6e56cf;
  --pb-patra-deep: #5b45b0;
  --pb-patra-3: #a78bfa;
  --pb-patra-glow: rgba(110, 86, 207, 0.55);

  align-items: center;
  padding: 7px 12px;
  border-top: 1px solid #171520 !important;
}

.patra-composer-tools {
  display: flex;
  align-items: center;
  gap: 3px;
}

.patra-composer-right {
  display: flex;
  align-items: center;
  gap: 10px;
}

.patra-composer-bar :deep(.left-wrap) {
  display: flex;
  align-items: center;
  gap: 3px;
}

.patra-composer-bar :deep(.patra-composer-tools button) {
  width: 31px;
  height: 31px;
  min-width: 31px;
  min-height: 31px;
  border-radius: 8px;
  color: var(--pb-text-3);
  background: transparent;
  border: none;
  transition: all 0.2s cubic-bezier(0.34, 1.56, 0.64, 1);
}

.patra-composer-bar :deep(.patra-composer-tools button:hover:not(:disabled)) {
  color: #ededf2;
  background: var(--pb-surface-2);
  transform: translateY(-2px);
}

.patra-composer-bar
  :deep(.patra-composer-right > button:not(.patra-composer-send)) {
  width: 31px;
  height: 31px;
  min-width: 31px;
  min-height: 31px;
  border-radius: 8px;
  color: var(--pb-text-3);
  background: transparent;
  border: none;
}

.patra-composer-bar
  :deep(
    .patra-composer-right
      > button:not(.patra-composer-send):hover:not(:disabled)
  ) {
  color: #ededf2;
  background: var(--pb-surface-2);
  transform: translateY(-2px);
}

.patra-composer-bar :deep(.patra-composer-send) {
  width: auto;
  min-width: unset;
  min-height: unset;
  height: auto;
  font-size: 13px;
  font-weight: 600;
  padding: 8px 16px;
  border-radius: 9px;
  background: linear-gradient(135deg, var(--pb-patra), var(--pb-patra-deep));
  color: #fff;
  border: none;
  box-shadow: 0 3px 12px var(--pb-patra-glow);
  transform: none;
}

.patra-composer-bar :deep(.patra-composer-send:hover:not(:disabled)) {
  filter: brightness(1.12);
  transform: translateY(-2px);
  box-shadow: 0 6px 20px var(--pb-patra-glow);
}

.patra-composer-bar :deep(.patra-composer-send:disabled) {
  opacity: 0.45;
  filter: none;
  transform: none;
  box-shadow: none;
}

.patra-composer-bar.is-note-mode :deep(.patra-composer-send) {
  background: rgba(227, 160, 8, 0.18);
  color: #e3a008;
  border: 1px solid rgba(227, 160, 8, 0.35);
  box-shadow: none;
}

.patra-composer-bar :deep(.file-uploads label) {
  cursor: pointer;
}
</style>
