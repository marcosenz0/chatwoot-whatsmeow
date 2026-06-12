<script>
import { useAlert } from 'dashboard/composables';
import { mapGetters } from 'vuex';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';
import ContextMenu from 'dashboard/components/ui/ContextMenu.vue';
import AddCannedModal from 'dashboard/routes/dashboard/settings/canned/AddCanned.vue';
import { useSnakeCase } from 'dashboard/composables/useTransformKeys';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import { conversationUrl, frontendURL } from '../../../helper/URLHelper';
import {
  ACCOUNT_EVENTS,
  CONVERSATION_EVENTS,
} from '../../../helper/AnalyticsHelper/events';
import MenuItem from '../../../components/widgets/conversation/contextMenu/menuItem.vue';
import { useTrack } from 'dashboard/composables';
import NextButton from 'dashboard/components-next/button/Button.vue';

export default {
  components: {
    AddCannedModal,
    MenuItem,
    ContextMenu,
    NextButton,
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
  emits: ['open', 'close', 'replyTo', 'react'],
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
      this.$emit('close', e);
    },
    handleTranslate() {
      const { locale: accountLocale } = this.getAccount(this.currentAccountId);
      const agentLocale = this.getUISettings?.locale;
      const targetLanguage = agentLocale || accountLocale || 'en';
      this.$store.dispatch('translateMessage', {
        conversationId: this.conversationId,
        messageId: this.messageId,
        targetLanguage,
      });
      useTrack(CONVERSATION_EVENTS.TRANSLATE_A_MESSAGE);
      this.handleClose();
    },
    handleReplyTo() {
      this.$emit('replyTo', this.message);
      this.handleClose();
    },
    handleReaction(emoji) {
      this.$emit('react', emoji);
      this.handleClose();
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
    <!-- Confirm Deletion -->
    <woot-delete-modal
      v-if="showDeleteModal && enabledOptions['delete']"
      v-model:show="showDeleteModal"
      class="context-menu--delete-modal"
      :on-close="closeDeleteModal"
      :on-confirm="confirmDeletion"
      :title="$t('CONVERSATION.CONTEXT_MENU.DELETE_CONFIRMATION.TITLE')"
      :message="$t('CONVERSATION.CONTEXT_MENU.DELETE_CONFIRMATION.MESSAGE')"
      :confirm-text="$t('CONVERSATION.CONTEXT_MENU.DELETE_CONFIRMATION.DELETE')"
      :reject-text="$t('CONVERSATION.CONTEXT_MENU.DELETE_CONFIRMATION.CANCEL')"
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
        $t('CONVERSATION.CONTEXT_MENU.DELETE_FOR_EVERYONE_CONFIRMATION.MESSAGE')
      "
      :confirm-text="
        $t('CONVERSATION.CONTEXT_MENU.DELETE_FOR_EVERYONE_CONFIRMATION.DELETE')
      "
      :reject-text="
        $t('CONVERSATION.CONTEXT_MENU.DELETE_FOR_EVERYONE_CONFIRMATION.CANCEL')
      "
    />
    <woot-modal
      v-if="showEditModal && enabledOptions['edit']"
      v-model:show="showEditModal"
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
    <NextButton
      v-if="!hideButton"
      ghost
      slate
      sm
      icon="i-lucide-chevron-down"
      class="invisible rounded-full bg-n-alpha-2 group-hover/message:visible focus:visible"
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
          v-if="enabledOptions['copy']"
          :option="{
            icon: 'clipboard',
            label: $t('CONVERSATION.CONTEXT_MENU.COPY'),
          }"
          variant="icon"
          @click.stop="handleCopy"
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
