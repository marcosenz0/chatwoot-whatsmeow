<script>
import { useAlert } from 'dashboard/composables';
import { mapGetters } from 'vuex';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';
import ContextMenu from 'dashboard/components/ui/ContextMenu.vue';
import AddCannedModal from 'dashboard/routes/dashboard/settings/canned/AddCanned.vue';
import { useSnakeCase } from 'dashboard/composables/useTransformKeys';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import { parseAPIErrorResponse } from 'dashboard/store/utils/api';
import { conversationUrl, frontendURL } from '../../../helper/URLHelper';
import {
  ACCOUNT_EVENTS,
  CONVERSATION_EVENTS,
} from '../../../helper/AnalyticsHelper/events';
import MenuItem from '../../../components/widgets/conversation/contextMenu/menuItem.vue';
import { useTrack } from 'dashboard/composables';
import NextButton from 'dashboard/components-next/button/Button.vue';
import ReportCaptainMessageDialog from './ReportCaptainMessageDialog.vue';

const AUDIO_FILE_EXTENSIONS = [
  'aac',
  'm4a',
  'mp3',
  'oga',
  'ogg',
  'opus',
  'wav',
  'webm',
];

export default {
  components: {
    AddCannedModal,
    MenuItem,
    ContextMenu,
    NextButton,
    ReportCaptainMessageDialog,
  },
  props: {
    message: {
      type: Object,
      required: true,
    },
    isOpen: {
      type: Boolean,
      default: false,
    },
    enabledOptions: {
      type: Object,
      default: () => ({}),
    },
    contextMenuPosition: {
      type: Object,
      default: () => ({}),
    },
    hideButton: {
      type: Boolean,
      default: false,
    },
  },
  emits: ['open', 'close', 'replyTo', 'react', 'select'],
  setup() {
    const { getPlainText } = useMessageFormatter();

    return {
      getPlainText,
    };
  },
  data() {
    return {
      isCannedResponseModalOpen: false,
      showDeleteModal: false,
      showPermanentDeleteModal: false,
      showDeleteForEveryoneModal: false,
      showEditModal: false,
      editableContent: '',
      isEditingMessage: false,
      quickReactionEmojis: [
        '\u{1F44D}',
        '\u{2764}\u{FE0F}',
        '\u{1F602}',
        '\u{1F62E}',
        '\u{1F622}',
        '\u{1F64F}',
      ],
    };
  },
  computed: {
    ...mapGetters({
      getAccount: 'accounts/getAccount',
      currentAccountId: 'getCurrentAccountId',
      getUISettings: 'getUISettings',
    }),
    plainTextContent() {
      return this.getPlainText(this.messageContent);
    },
    conversationId() {
      return this.message.conversation_id ?? this.message.conversationId;
    },
    messageId() {
      return this.message.id;
    },
    messageContent() {
      return this.message.content;
    },
    contentAttributes() {
      return useSnakeCase(
        this.message.content_attributes ?? this.message.contentAttributes
      );
    },
    attachments() {
      return this.message.attachments || [];
    },
    audioAttachment() {
      return this.attachments.find(attachment => {
        const fileType = attachment.file_type || attachment.fileType;
        const dataUrl = attachment.data_url || attachment.dataUrl;
        const contentType = (
          attachment.content_type ||
          attachment.contentType ||
          ''
        ).toLowerCase();
        const extension = (attachment.extension || '').toLowerCase();

        return (
          dataUrl &&
          (fileType === 'audio' ||
            contentType.startsWith('audio/') ||
            AUDIO_FILE_EXTENSIONS.includes(extension))
        );
      });
    },
    audioDownloadUrl() {
      return this.audioAttachment?.data_url || this.audioAttachment?.dataUrl;
    },
    audioDownloadFileName() {
      const attachment = this.audioAttachment || {};
      const configuredName =
        attachment.file_name ||
        attachment.fileName ||
        attachment.filename ||
        attachment.name;
      if (configuredName) return configuredName;

      const extension = attachment.extension || 'ogg';
      try {
        const url = new URL(this.audioDownloadUrl, window.location.origin);
        const pathName = decodeURIComponent(url.pathname);
        const fileName = pathName.split('/').filter(Boolean).pop();
        if (fileName && fileName.includes('.')) return fileName;
      } catch {
        // Ignore URL parse errors and use the fallback filename below.
      }

      return `audio-${this.messageId}.${extension}`;
    },
    canSubmitEdit() {
      return this.editableContent.trim().length > 0 && !this.isEditingMessage;
    },
  },
  methods: {
    async copyLinkToMessage() {
      const fullConversationURL =
        window.chatwootConfig.hostURL +
        frontendURL(
          conversationUrl({
            id: this.conversationId,
            accountId: this.currentAccountId,
          })
        );
      await copyTextToClipboard(
        `${fullConversationURL}?messageId=${this.messageId}`
      );
      useAlert(this.$t('CONVERSATION.CONTEXT_MENU.LINK_COPIED'));
      this.handleClose();
    },
    async handleCopy() {
      await copyTextToClipboard(this.plainTextContent);
      useAlert(this.$t('CONTACT_PANEL.COPY_SUCCESSFUL'));
      this.handleClose();
    },
    showCannedResponseModal() {
      useTrack(ACCOUNT_EVENTS.ADDED_TO_CANNED_RESPONSE);
      this.isCannedResponseModalOpen = true;
    },
    hideCannedResponseModal() {
      this.isCannedResponseModalOpen = false;
      this.handleClose();
    },
    handleOpen(e) {
      this.$emit('open', e);
    },
    handleClose(e) {
      document.activeElement?.blur?.();
      this.$emit('close', e);
    },
    async handleTranslate() {
      const { locale: accountLocale } = this.getAccount(this.currentAccountId);
      const agentLocale = this.getUISettings?.locale;
      const targetLanguage = agentLocale || accountLocale || 'en';
      try {
        await this.$store.dispatch('translateMessage', {
          conversationId: this.conversationId,
          messageId: this.messageId,
          targetLanguage,
        });
        useTrack(CONVERSATION_EVENTS.TRANSLATE_A_MESSAGE);
      } catch (error) {
        useAlert(parseAPIErrorResponse(error));
      }
      this.handleClose();
    },
    handleReplyTo() {
      this.$emit('replyTo', this.message);
      this.handleClose();
    },
    handleSelect() {
      this.$emit('select', this.message);
      this.handleClose();
    },
    selectMenuLabel() {
      const locale = String(this.$i18n?.locale || '').toLowerCase();
      if (locale.startsWith('pt')) return 'Selecionar';

      return this.$t('CONVERSATION.CONTEXT_MENU.SELECT');
    },
    handleReaction(emoji) {
      this.$emit('react', emoji);
      this.handleClose();
    },
    triggerFileDownload(url, fileName) {
      const link = document.createElement('a');
      link.href = url;
      link.download = fileName;
      link.rel = 'noreferrer noopener nofollow';
      link.style.display = 'none';
      document.body.appendChild(link);
      link.click();
      link.remove();
    },
    async downloadAudio() {
      const url = this.audioDownloadUrl;
      if (!url) return;

      this.handleClose();

      try {
        const response = await fetch(url, { credentials: 'include' });
        if (!response.ok) throw new Error('Could not download audio');

        const blobUrl = URL.createObjectURL(await response.blob());
        this.triggerFileDownload(blobUrl, this.audioDownloadFileName);
        window.setTimeout(() => URL.revokeObjectURL(blobUrl), 1000);
      } catch {
        try {
          this.triggerFileDownload(url, this.audioDownloadFileName);
        } catch {
          useAlert(this.$t('CONVERSATION.CONTEXT_MENU.DOWNLOAD_AUDIO_ERROR'));
        }
      }
    },
    openDeleteModal() {
      this.handleClose();
      this.showDeleteModal = true;
    },
    openPermanentDeleteModal() {
      this.handleClose();
      this.showPermanentDeleteModal = true;
    },
    openDeleteForEveryoneModal() {
      this.handleClose();
      this.showDeleteForEveryoneModal = true;
    },
    openEditModal() {
      this.handleClose();
      this.editableContent = this.messageContent || '';
      this.showEditModal = true;
      this.$nextTick(() => this.$refs.editTextArea?.focus());
    },
    closeEditModal() {
      if (this.isEditingMessage) return;

      this.showEditModal = false;
      this.editableContent = '';
    },
    async confirmEdit() {
      if (!this.canSubmitEdit) return;

      this.isEditingMessage = true;
      try {
        await this.$store.dispatch('editMessage', {
          conversationId: this.conversationId,
          messageId: this.messageId,
          content: this.editableContent.trim(),
        });
        useAlert(this.$t('CONVERSATION.SUCCESS_EDIT_MESSAGE'));
        this.showEditModal = false;
      } catch (error) {
        useAlert(
          error?.response?.data?.error ||
            this.$t('CONVERSATION.FAIL_EDIT_MESSAGE')
        );
      } finally {
        this.isEditingMessage = false;
      }
    },
    async confirmDeletion() {
      try {
        await this.$store.dispatch('deleteMessage', {
          conversationId: this.conversationId,
          messageId: this.messageId,
        });
        useAlert(this.$t('CONVERSATION.SUCCESS_DELETE_MESSAGE'));
        this.handleClose();
      } catch (error) {
        useAlert(this.$t('CONVERSATION.FAIL_DELETE_MESSSAGE'));
      }
    },
    async confirmPermanentDeletion() {
      try {
        await this.$store.dispatch('deleteMessage', {
          conversationId: this.conversationId,
          messageId: this.messageId,
        });
        useAlert(this.$t('CONVERSATION.SUCCESS_PERMANENT_DELETE_MESSAGE'));
        this.handleClose();
      } catch (error) {
        useAlert(this.$t('CONVERSATION.FAIL_DELETE_MESSSAGE'));
      }
    },
    async confirmDeleteForEveryone() {
      try {
        await this.$store.dispatch('deleteMessageForEveryone', {
          conversationId: this.conversationId,
          messageId: this.messageId,
        });
        useAlert(this.$t('CONVERSATION.SUCCESS_DELETE_FOR_EVERYONE_MESSAGE'));
        this.handleClose();
      } catch (error) {
        useAlert(this.$t('CONVERSATION.FAIL_DELETE_FOR_EVERYONE_MESSAGE'));
      }
    },
    closeDeleteModal() {
      this.showDeleteModal = false;
    },
    closePermanentDeleteModal() {
      this.showPermanentDeleteModal = false;
    },
    closeDeleteForEveryoneModal() {
      this.showDeleteForEveryoneModal = false;
    },
    openReportDialog() {
      this.handleClose();
      this.$refs.reportDialog?.open();
    },
  },
};
</script>

<template>
  <div class="context-menu">
    <!-- Add To Canned Responses -->
    <woot-modal
      v-if="isCannedResponseModalOpen && enabledOptions['cannedResponse']"
      v-model:show="isCannedResponseModalOpen"
      :on-close="hideCannedResponseModal"
    >
      <AddCannedModal
        :response-content="plainTextContent"
        :on-close="hideCannedResponseModal"
      />
    </woot-modal>
    <Teleport to="body">
      <!-- Confirm Deletion -->
      <woot-delete-modal
        v-if="showDeleteModal && enabledOptions['delete']"
        v-model:show="showDeleteModal"
        class="context-menu--delete-modal"
        :on-close="closeDeleteModal"
        :on-confirm="confirmDeletion"
        :title="$t('CONVERSATION.CONTEXT_MENU.DELETE_CONFIRMATION.TITLE')"
        :message="$t('CONVERSATION.CONTEXT_MENU.DELETE_CONFIRMATION.MESSAGE')"
        :confirm-text="
          $t('CONVERSATION.CONTEXT_MENU.DELETE_CONFIRMATION.DELETE')
        "
        :reject-text="
          $t('CONVERSATION.CONTEXT_MENU.DELETE_CONFIRMATION.CANCEL')
        "
      />
      <woot-delete-modal
        v-if="showPermanentDeleteModal && enabledOptions['permanentDelete']"
        v-model:show="showPermanentDeleteModal"
        class="context-menu--delete-modal"
        :on-close="closePermanentDeleteModal"
        :on-confirm="confirmPermanentDeletion"
        :title="
          $t('CONVERSATION.CONTEXT_MENU.PERMANENT_DELETE_CONFIRMATION.TITLE')
        "
        :message="
          $t('CONVERSATION.CONTEXT_MENU.PERMANENT_DELETE_CONFIRMATION.MESSAGE')
        "
        :confirm-text="
          $t('CONVERSATION.CONTEXT_MENU.PERMANENT_DELETE_CONFIRMATION.DELETE')
        "
        :reject-text="
          $t('CONVERSATION.CONTEXT_MENU.PERMANENT_DELETE_CONFIRMATION.CANCEL')
        "
      />
      <woot-delete-modal
        v-if="showDeleteForEveryoneModal && enabledOptions['deleteForEveryone']"
        v-model:show="showDeleteForEveryoneModal"
        class="context-menu--delete-modal"
        :on-close="closeDeleteForEveryoneModal"
        :on-confirm="confirmDeleteForEveryone"
        :title="
          $t('CONVERSATION.CONTEXT_MENU.DELETE_FOR_EVERYONE_CONFIRMATION.TITLE')
        "
        :message="
          $t(
            'CONVERSATION.CONTEXT_MENU.DELETE_FOR_EVERYONE_CONFIRMATION.MESSAGE'
          )
        "
        :confirm-text="
          $t(
            'CONVERSATION.CONTEXT_MENU.DELETE_FOR_EVERYONE_CONFIRMATION.DELETE'
          )
        "
        :reject-text="
          $t(
            'CONVERSATION.CONTEXT_MENU.DELETE_FOR_EVERYONE_CONFIRMATION.CANCEL'
          )
        "
      />
    </Teleport>
    <Teleport to="body">
      <woot-modal
        v-if="showEditModal && enabledOptions['edit']"
        v-model:show="showEditModal"
        :show-close-button="false"
        :on-close="closeEditModal"
      >
        <div class="flex flex-col gap-5 p-6 text-n-slate-12">
          <div class="flex items-center justify-between gap-3">
            <h3 class="m-0 text-base font-semibold">
              {{ $t('CONVERSATION.EDIT_MESSAGE.TITLE') }}
            </h3>
            <NextButton
              ghost
              slate
              sm
              icon="i-lucide-x"
              :disabled="isEditingMessage"
              @click="closeEditModal"
            />
          </div>
          <textarea
            ref="editTextArea"
            v-model="editableContent"
            class="reset-base min-h-24 w-full resize-y rounded-lg border border-n-weak bg-n-alpha-2 px-3 py-2 text-sm leading-5 text-n-slate-12 outline-none focus:border-n-brand"
            :placeholder="$t('CONVERSATION.EDIT_MESSAGE.PLACEHOLDER')"
            @keydown.enter.exact.prevent="confirmEdit"
          />
          <div class="flex items-center justify-end gap-2">
            <NextButton
              faded
              slate
              :label="$t('CONVERSATION.EDIT_MESSAGE.CANCEL')"
              :disabled="isEditingMessage"
              @click="closeEditModal"
            />
            <NextButton
              solid
              blue
              icon="i-lucide-check"
              :label="$t('CONVERSATION.EDIT_MESSAGE.SAVE')"
              :is-loading="isEditingMessage"
              :disabled="!canSubmitEdit"
              @click="confirmEdit"
            />
          </div>
        </div>
      </woot-modal>
    </Teleport>
    <NextButton
      v-if="!hideButton"
      ghost
      slate
      xs
      icon="i-lucide-chevron-down"
      class="invisible rounded-full bg-n-alpha-2 shadow-sm group-hover/message:visible focus:visible"
      @click="handleOpen"
    />
    <ContextMenu
      v-if="isOpen && !isCannedResponseModalOpen"
      :x="contextMenuPosition.x"
      :y="contextMenuPosition.y"
      @close="handleClose"
    >
      <div class="menu-container">
        <div
          v-if="enabledOptions['reaction']"
          class="flex items-center gap-1 px-1 py-1"
        >
          <button
            v-for="emoji in quickReactionEmojis"
            :key="emoji"
            type="button"
            class="flex size-7 items-center justify-center rounded-full text-base hover:bg-n-alpha-2"
            @mousedown.prevent.stop="handleReaction(emoji)"
            @click.prevent.stop
          >
            {{ emoji }}
          </button>
        </div>
        <hr v-if="enabledOptions['reaction']" />
        <MenuItem
          v-if="enabledOptions['replyTo']"
          :option="{
            icon: 'arrow-reply',
            label: $t('CONVERSATION.CONTEXT_MENU.REPLY_TO'),
          }"
          variant="icon"
          @click.stop="handleReplyTo"
        />
        <MenuItem
          v-if="enabledOptions['downloadAudio']"
          :option="{
            icon: 'i-lucide-download',
            label: $t('CONVERSATION.CONTEXT_MENU.DOWNLOAD_AUDIO'),
          }"
          variant="icon"
          @click.stop="downloadAudio"
        />
        <MenuItem
          v-if="enabledOptions['copy']"
          :option="{
            icon: 'clipboard',
            label: $t('CONVERSATION.CONTEXT_MENU.COPY'),
          }"
          variant="icon"
          @click.stop="handleCopy"
        />
        <MenuItem
          v-if="enabledOptions['select']"
          :option="{
            icon: 'i-lucide-square-check',
            label: selectMenuLabel(),
          }"
          variant="icon"
          @click.stop="handleSelect"
        />
        <MenuItem
          v-if="enabledOptions['translate']"
          :option="{
            icon: 'translate',
            label: $t('CONVERSATION.CONTEXT_MENU.TRANSLATE'),
          }"
          variant="icon"
          @click.stop="handleTranslate"
        />
        <MenuItem
          v-if="enabledOptions['edit']"
          :option="{
            icon: 'edit',
            label: $t('CONVERSATION.CONTEXT_MENU.EDIT'),
          }"
          variant="icon"
          @click.stop="openEditModal"
        />
        <hr />
        <MenuItem
          v-if="enabledOptions['copyLink']"
          :option="{
            icon: 'link',
            label: $t('CONVERSATION.CONTEXT_MENU.COPY_PERMALINK'),
          }"
          variant="icon"
          @click.stop="copyLinkToMessage"
        />
        <MenuItem
          v-if="enabledOptions['cannedResponse']"
          :option="{
            icon: 'comment-add',
            label: $t('CONVERSATION.CONTEXT_MENU.CREATE_A_CANNED_RESPONSE'),
          }"
          variant="icon"
          @click.stop="showCannedResponseModal"
        />
        <hr
          v-if="
            enabledOptions['delete'] ||
            enabledOptions['deleteForEveryone'] ||
            enabledOptions['permanentDelete']
          "
        />
        <MenuItem
          v-if="enabledOptions['deleteForEveryone']"
          :option="{
            icon: 'delete',
            label: $t('CONVERSATION.CONTEXT_MENU.DELETE_FOR_EVERYONE'),
          }"
          variant="icon"
          @click.stop="openDeleteForEveryoneModal"
        />
        <hr v-if="enabledOptions['report']" />
        <MenuItem
          v-if="enabledOptions['report']"
          :option="{
            icon: 'warning',
            label: $t('CONVERSATION.CONTEXT_MENU.REPORT_MESSAGE.LABEL'),
          }"
          variant="icon"
          @click.stop="openReportDialog"
        />
        <MenuItem
          v-if="enabledOptions['delete']"
          :option="{
            icon: 'delete',
            label: $t('CONVERSATION.CONTEXT_MENU.DELETE'),
          }"
          variant="icon"
          @click.stop="openDeleteModal"
        />
        <MenuItem
          v-if="enabledOptions['permanentDelete']"
          :option="{
            icon: 'delete',
            label: $t('CONVERSATION.CONTEXT_MENU.PERMANENT_DELETE'),
          }"
          variant="icon"
          @click.stop="openPermanentDeleteModal"
        />
      </div>
    </ContextMenu>
    <ReportCaptainMessageDialog
      v-if="enabledOptions['report']"
      ref="reportDialog"
      :message-id="messageId"
    />
  </div>
</template>

<style lang="scss" scoped>
.menu-container {
  @apply p-1 bg-n-background shadow-xl rounded-md;

  hr:first-child {
    @apply hidden;
  }

  hr {
    @apply m-1 border-b border-solid border-n-strong;
  }
}

.context-menu--delete-modal {
  :deep(.modal-container) {
    @apply max-w-[30rem];

    h2 {
      @apply font-medium text-base;
    }
  }
}
</style>
