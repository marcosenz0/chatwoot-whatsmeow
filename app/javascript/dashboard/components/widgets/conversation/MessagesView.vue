<script>
import { ref, provide, useTemplateRef } from 'vue';
import { useElementSize } from '@vueuse/core';
// composable
import { useLabelSuggestions } from 'dashboard/composables/useLabelSuggestions';
import { useSnakeCase } from 'dashboard/composables/useTransformKeys';

// components
import ReplyBox from './ReplyBox.vue';
import MessageList from 'next/message/MessageList.vue';
import ConversationLabelSuggestion from './conversation/LabelSuggestion.vue';
import Banner from 'dashboard/components/ui/Banner.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ResizableEditorWrapper from './ResizableEditorWrapper.vue';
import MessageSelectionToolbar from './MessageSelectionToolbar.vue';
import ForwardMessagesModal from './ForwardMessagesModal.vue';

// stores and apis
import { mapGetters } from 'vuex';
import InboxesAPI from 'dashboard/api/inboxes';

// mixins
import inboxMixin, { INBOX_FEATURES } from 'shared/mixins/inboxMixin';

// utils
import { emitter } from 'shared/helpers/mitt';
import { getTypingUsersText } from '../../../helper/commons';
import { calculateScrollTop } from './helpers/scrollTopCalculationHelper';
import { LocalStorage } from 'shared/helpers/localStorage';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';
import { useAlert } from 'dashboard/composables';
import {
  filterDuplicateSourceMessages,
  getReadMessages,
  getUnreadMessages,
} from 'dashboard/helper/conversationHelper';

// constants
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { REPLY_POLICY } from 'shared/constants/links';
import wootConstants from 'dashboard/constants/globals';
import { LOCAL_STORAGE_KEYS } from 'dashboard/constants/localStorage';
import { INBOX_TYPES } from 'dashboard/helper/inbox';

export default {
  components: {
    MessageList,
    ReplyBox,
    Banner,
    ConversationLabelSuggestion,
    Spinner,
    ResizableEditorWrapper,
    MessageSelectionToolbar,
    ForwardMessagesModal,
  },
  mixins: [inboxMixin],
  setup() {
    const conversationPanelRef = ref(null);
    const resizableEditorWrapperRef = ref(null);
    const messagesViewRef = useTemplateRef('messagesViewRef');
    const topBannerRef = useTemplateRef('topBannerRef');
    const { height: containerHeight } = useElementSize(messagesViewRef);
    const { height: topBannerHeight } = useElementSize(topBannerRef);
    const { getPlainText } = useMessageFormatter();

    const {
      captainTasksEnabled,
      isLabelSuggestionFeatureEnabled,
      getLabelSuggestions,
    } = useLabelSuggestions();

    provide('contextMenuElementTarget', conversationPanelRef);

    return {
      captainTasksEnabled,
      getLabelSuggestions,
      isLabelSuggestionFeatureEnabled,
      conversationPanelRef,
      resizableEditorWrapperRef,
      messagesViewRef,
      topBannerRef,
      containerHeight,
      topBannerHeight,
      getPlainText,
    };
  },
  data() {
    return {
      isLoadingPrevious: true,
      heightBeforeLoad: null,
      conversationPanel: null,
      hasUserScrolled: false,
      isProgrammaticScroll: false,
      messageSentSinceOpened: false,
      labelSuggestions: [],
      isMessageSelectionMode: false,
      selectedMessageIds: [],
      showBulkDeleteModal: false,
      isBulkDeleting: false,
      isForwardModalOpen: false,
      isForwardingMessages: false,
    };
  },

  computed: {
    ...mapGetters({
      currentChat: 'getSelectedChat',
      currentUserId: 'getCurrentUserID',
      listLoadingStatus: 'getAllMessagesLoaded',
      currentAccountId: 'getCurrentAccountId',
      allConversations: 'getAllConversations',
      selectedChatAttachments: 'getSelectedChatAttachments',
    }),
    isOpen() {
      return this.currentChat?.status === wootConstants.STATUS_TYPE.OPEN;
    },
    shouldShowLabelSuggestions() {
      return (
        this.isOpen &&
        this.captainTasksEnabled &&
        this.isLabelSuggestionFeatureEnabled &&
        !this.messageSentSinceOpened
      );
    },
    inboxId() {
      return this.currentChat.inbox_id;
    },
    inbox() {
      return this.$store.getters['inboxes/getInbox'](this.inboxId);
    },
    typingUsersList() {
      const userList = this.$store.getters[
        'conversationTypingStatus/getUserList'
      ](this.currentChat.id);
      return userList;
    },
    isAnyoneTyping() {
      const userList = this.typingUsersList;
      return userList.length !== 0;
    },
    typingUserNames() {
      const userList = this.typingUsersList;
      if (this.isAnyoneTyping) {
        const [i18nKey, params] = getTypingUsersText(userList);
        return this.$t(i18nKey, params);
      }

      return '';
    },
    getMessages() {
      const messages = this.currentChat.messages || [];
      if (this.isAWhatsAppChannel) {
        return filterDuplicateSourceMessages(messages);
      }
      return messages;
    },
    readMessages() {
      return getReadMessages(
        this.getMessages,
        this.currentChat.agent_last_seen_at
      );
    },
    unReadMessages() {
      return getUnreadMessages(
        this.getMessages,
        this.currentChat.agent_last_seen_at
      );
    },
    shouldShowSpinner() {
      return (
        (this.currentChat && this.currentChat.dataFetched === undefined) ||
        (!this.listLoadingStatus && this.isLoadingPrevious)
      );
    },
    // Check there is a instagram inbox exists with the same instagram_id
    hasDuplicateInstagramInbox() {
      const instagramId = this.inbox.instagram_id;
      const { additional_attributes: additionalAttributes = {} } = this.inbox;
      const instagramInbox =
        this.$store.getters['inboxes/getInstagramInboxByInstagramId'](
          instagramId
        );

      return (
        this.inbox.channel_type === INBOX_TYPES.FB &&
        additionalAttributes.type === 'instagram_direct_message' &&
        instagramInbox
      );
    },

    replyWindowBannerMessage() {
      if (this.isAWhatsAppChannel) {
        return this.$t('CONVERSATION.TWILIO_WHATSAPP_CAN_REPLY');
      }
      if (this.isAPIInbox) {
        const { additional_attributes: additionalAttributes = {} } = this.inbox;
        if (additionalAttributes) {
          const {
            agent_reply_time_window_message: agentReplyTimeWindowMessage,
            agent_reply_time_window: agentReplyTimeWindow,
          } = additionalAttributes;
          return (
            agentReplyTimeWindowMessage ||
            this.$t('CONVERSATION.API_HOURS_WINDOW', {
              hours: agentReplyTimeWindow,
            })
          );
        }
        return '';
      }
      return this.$t('CONVERSATION.CANNOT_REPLY');
    },
    replyWindowLink() {
      if (this.isAFacebookInbox || this.isAnInstagramChannel) {
        return REPLY_POLICY.FACEBOOK;
      }
      if (this.isAWhatsAppCloudChannel) {
        return REPLY_POLICY.WHATSAPP_CLOUD;
      }
      if (this.isATiktokChannel) {
        return REPLY_POLICY.TIKTOK;
      }
      if (!this.isAPIInbox) {
        return REPLY_POLICY.TWILIO_WHATSAPP;
      }
      return '';
    },
    replyWindowLinkText() {
      if (
        this.isAWhatsAppChannel ||
        this.isAFacebookInbox ||
        this.isAnInstagramChannel
      ) {
        return this.$t('CONVERSATION.24_HOURS_WINDOW');
      }
      if (this.isATiktokChannel) {
        return this.$t('CONVERSATION.48_HOURS_WINDOW');
      }
      if (!this.isAPIInbox) {
        return this.$t('CONVERSATION.TWILIO_WHATSAPP_24_HOURS_WINDOW');
      }
      return '';
    },
    unreadMessageCount() {
      return this.currentChat.unread_count || 0;
    },
    unreadMessageLabel() {
      const count =
        this.unreadMessageCount > 9 ? '9+' : this.unreadMessageCount;
      const label =
        this.unreadMessageCount > 1
          ? 'CONVERSATION.UNREAD_MESSAGES'
          : 'CONVERSATION.UNREAD_MESSAGE';
      return `${count} ${this.$t(label)}`;
    },
    inboxSupportsReplyTo() {
      const incoming = this.inboxHasFeature(INBOX_FEATURES.REPLY_TO);
      const outgoing =
        this.inboxHasFeature(INBOX_FEATURES.REPLY_TO_OUTGOING) &&
        !this.is360DialogWhatsAppChannel;

      return { incoming, outgoing };
    },
    selectedMessages() {
      return this.getMessages.filter(message =>
        this.selectedMessageIds.includes(message.id)
      );
    },
    forwardableSelectedMessages() {
      return this.selectedMessages.filter(message =>
        this.isForwardableMessage(message)
      );
    },
    canForwardSelectedMessages() {
      return this.forwardableSelectedMessages.length > 0;
    },
  },

  watch: {
    currentChat(newChat, oldChat) {
      if (newChat.id === oldChat.id) {
        return;
      }
      this.fetchAllAttachmentsFromCurrentChat();
      this.fetchSuggestions();
      this.messageSentSinceOpened = false;
      this.resetReplyEditorHeight();
      this.clearMessageSelection();
    },
  },

  created() {
    emitter.on(BUS_EVENTS.SCROLL_TO_MESSAGE, this.onScrollToMessage);
    // when a message is sent we set the flag to true this hides the label suggestions,
    // until the chat is changed and the flag is reset in the watch for currentChat
    emitter.on(BUS_EVENTS.MESSAGE_SENT, () => {
      this.messageSentSinceOpened = true;
    });
  },

  mounted() {
    this.addScrollListener();
    this.fetchAllAttachmentsFromCurrentChat();
    this.fetchSuggestions();
  },

  unmounted() {
    this.removeBusListeners();
    this.removeScrollListener();
  },

  methods: {
    async fetchSuggestions() {
      // start empty, this ensures that the label suggestions are not shown
      this.labelSuggestions = [];

      if (this.isLabelSuggestionDismissed()) {
        return;
      }

      // Early exit if conversation already has labels - no need to suggest more
      const existingLabels = this.currentChat?.labels || [];
      if (existingLabels.length > 0) return;

      if (!this.captainTasksEnabled || !this.isLabelSuggestionFeatureEnabled) {
        return;
      }

      this.labelSuggestions = await this.getLabelSuggestions();

      // once the labels are fetched, we need to scroll to bottom
      // but we need to wait for the DOM to be updated
      // so we use the nextTick method
      this.$nextTick(() => {
        // this param is added to route, telling the UI to navigate to the message
        // it is triggered by the SCROLL_TO_MESSAGE method
        // see setActiveChat on ConversationView.vue for more info
        const { messageId } = this.$route.query;

        // only trigger the scroll to bottom if the user has not scrolled
        // and there's no active messageId that is selected in view
        if (!messageId && !this.hasUserScrolled) {
          this.scrollToBottom();
        }
      });
    },
    isLabelSuggestionDismissed() {
      return LocalStorage.getFlag(
        LOCAL_STORAGE_KEYS.DISMISSED_LABEL_SUGGESTIONS,
        this.currentAccountId,
        this.currentChat.id
      );
    },
    fetchAllAttachmentsFromCurrentChat() {
      this.$store.dispatch('fetchAllAttachments', this.currentChat.id);
    },
    removeBusListeners() {
      emitter.off(BUS_EVENTS.SCROLL_TO_MESSAGE, this.onScrollToMessage);
    },
    onScrollToMessage({ messageId = '' } = {}) {
      this.$nextTick(() => {
        const messageElement = document.getElementById('message' + messageId);
        if (messageElement) {
          this.isProgrammaticScroll = true;
          messageElement.scrollIntoView({ behavior: 'smooth' });
          this.fetchPreviousMessages();
        } else {
          this.scrollToBottom();
        }
      });
      this.makeMessagesRead();
    },
    addScrollListener() {
      this.conversationPanel = this.$el.querySelector('.conversation-panel');
      this.setScrollParams();
      this.conversationPanel.addEventListener('scroll', this.handleScroll);
      this.$nextTick(() => this.scrollToBottom());
      this.isLoadingPrevious = false;
    },
    removeScrollListener() {
      this.conversationPanel.removeEventListener('scroll', this.handleScroll);
    },
    scrollToBottom() {
      this.isProgrammaticScroll = true;
      let relevantMessages = [];

      // label suggestions are not part of the messages list
      // so we need to handle them separately
      let labelSuggestions =
        this.conversationPanel.querySelector('.label-suggestion');

      // if there are unread messages, scroll to the first unread message
      if (this.unreadMessageCount > 0) {
        // capturing only the unread messages
        relevantMessages =
          this.conversationPanel.querySelectorAll('.message--unread');
      } else if (labelSuggestions) {
        // when scrolling to the bottom, the label suggestions is below the last message
        // so we scroll there if there are no unread messages
        // Unread messages always take the highest priority
        relevantMessages = [labelSuggestions];
      } else {
        // if there are no unread messages or label suggestion, scroll to the last message
        // capturing last message from the messages list
        relevantMessages = Array.from(
          this.conversationPanel.querySelectorAll('.message--read')
        ).slice(-1);
      }

      this.conversationPanel.scrollTop = calculateScrollTop(
        this.conversationPanel.scrollHeight,
        this.$el.scrollHeight,
        relevantMessages
      );
    },
    setScrollParams() {
      this.heightBeforeLoad = this.conversationPanel.scrollHeight;
      this.scrollTopBeforeLoad = this.conversationPanel.scrollTop;
    },

    async fetchPreviousMessages(scrollTop = 0) {
      this.setScrollParams();
      const shouldLoadMoreMessages =
        this.currentChat.dataFetched === true &&
        !this.listLoadingStatus &&
        !this.isLoadingPrevious;

      if (
        scrollTop < 100 &&
        !this.isLoadingPrevious &&
        shouldLoadMoreMessages
      ) {
        this.isLoadingPrevious = true;
        try {
          await this.$store.dispatch('fetchPreviousMessages', {
            conversationId: this.currentChat.id,
            before: this.currentChat.messages[0].id,
          });
          const heightDifference =
            this.conversationPanel.scrollHeight - this.heightBeforeLoad;
          this.conversationPanel.scrollTop =
            this.scrollTopBeforeLoad + heightDifference;
          this.setScrollParams();
        } catch (error) {
          // Ignore Error
        } finally {
          this.isLoadingPrevious = false;
        }
      }
    },

    handleScroll(e) {
      if (this.isProgrammaticScroll) {
        // Reset the flag
        this.isProgrammaticScroll = false;
        this.hasUserScrolled = false;
      } else {
        this.hasUserScrolled = true;
      }
      emitter.emit(BUS_EVENTS.ON_MESSAGE_LIST_SCROLL);
      this.fetchPreviousMessages(e.target.scrollTop);
    },

    makeMessagesRead() {
      this.$store.dispatch('markMessagesRead', { id: this.currentChat.id });
    },
    async handleMessageRetry(message) {
      if (!message) return;
      const payload = useSnakeCase(message);
      await this.$store.dispatch('sendMessageWithData', payload);
    },
    messagePlainText(message) {
      return this.getPlainText(message.content || '').trim();
    },
    messageAttachments(message) {
      const inlineAttachments = message.attachments || [];
      const inlineAttachmentIds = new Set(
        inlineAttachments
          .map(attachment => Number(attachment.id))
          .filter(Number.isFinite)
      );
      const messageId = Number(message.id || message.message_id);
      const chatAttachments = this.selectedChatAttachments || [];
      const storedAttachments = chatAttachments.filter(attachment => {
        const attachmentMessageId = Number(
          attachment.message_id || attachment.messageId
        );
        const attachmentId = Number(attachment.id);
        return (
          attachmentMessageId === messageId &&
          !inlineAttachmentIds.has(attachmentId)
        );
      });

      return [...inlineAttachments, ...storedAttachments];
    },
    messageCopyText(message) {
      const text = this.messagePlainText(message);
      const attachmentLines = this.messageAttachments(message)
        .map((attachment, index) => {
          const fileName = this.attachmentFileName(attachment, index);
          const url = this.attachmentUrl(attachment);
          return url ? `${fileName}: ${url}` : fileName;
        })
        .filter(Boolean);

      return [text, ...attachmentLines].filter(Boolean).join('\n');
    },
    isForwardableMessage(message) {
      return (
        this.messagePlainText(message).length ||
        this.messageAttachments(message).length
      );
    },
    attachmentUrl(attachment) {
      return (
        attachment.data_url ||
        attachment.dataUrl ||
        attachment.download_url ||
        attachment.downloadUrl ||
        attachment.file_url ||
        attachment.fileUrl ||
        attachment.url
      );
    },
    attachmentFileName(attachment, fallbackIndex = 0) {
      const configuredName =
        attachment.file_name ||
        attachment.fileName ||
        attachment.filename ||
        attachment.name;
      if (configuredName) return configuredName;

      const url = this.attachmentUrl(attachment);
      if (url) {
        try {
          const parsedUrl = new URL(url, window.location.origin);
          const pathName = decodeURIComponent(parsedUrl.pathname);
          const fileName = pathName.split('/').filter(Boolean).pop();
          if (fileName) return fileName;
        } catch {
          // Fall back to a generated filename below.
        }
      }

      const extension = attachment.extension
        ? `.${attachment.extension.replace(/^\./, '')}`
        : '';
      return `forwarded-attachment-${fallbackIndex + 1}${extension}`;
    },
    attachmentContentType(attachment, blob) {
      return (
        attachment.content_type ||
        attachment.contentType ||
        blob.type ||
        'application/octet-stream'
      );
    },
    async attachmentToFile(attachment, fallbackIndex = 0) {
      const url = this.attachmentUrl(attachment);
      if (!url) throw new Error('Attachment URL not available');

      const response = await fetch(url, { credentials: 'include' });
      if (!response.ok) throw new Error('Attachment download failed');

      const blob = await response.blob();
      const fileName = this.attachmentFileName(attachment, fallbackIndex);
      const contentType = this.attachmentContentType(attachment, blob);

      return new File([blob], fileName, { type: contentType });
    },
    async sendForwardedMessagePayload({ conversationId, message, file }) {
      const payload = {
        conversationId,
        message,
        private: false,
      };

      if (file) {
        payload.file = file;
        payload.files = [file];
      }

      await this.$store.dispatch('createPendingMessageAndSend', payload);
    },
    async forwardMessageToConversation(conversationId, message) {
      const text = this.messagePlainText(message);
      const attachments = this.messageAttachments(message);

      if (!attachments.length) {
        await this.sendForwardedMessagePayload({
          conversationId,
          message: text,
        });
        return;
      }

      const files = await Promise.all(
        attachments.map((attachment, index) =>
          this.attachmentToFile(attachment, index)
        )
      );

      await files.reduce((promise, file, index) => {
        const caption = index === 0 ? text : '';
        return promise.then(() =>
          this.sendForwardedMessagePayload({
            conversationId,
            message: caption,
            file,
          })
        );
      }, Promise.resolve());
    },
    isPortugueseLocale() {
      return String(this.$i18n?.locale || '')
        .toLowerCase()
        .startsWith('pt');
    },
    messageSelectionText(key) {
      if (this.isPortugueseLocale()) {
        if (key === 'COPIED') return 'Mensagens copiadas';
        if (key === 'DELETED') return 'Mensagens apagadas';
        if (key === 'FORWARDED') return 'Mensagens encaminhadas';
        if (key === 'FORWARD_FAILED') {
          return 'Não foi possível encaminhar as mensagens';
        }
        if (key === 'NO_FORWARDABLE') {
          return 'Selecione mensagens com texto, mídia ou anexo';
        }
        if (key === 'DELETE_TITLE') return 'Apagar mensagens selecionadas?';
        if (key === 'DELETE_MESSAGE') {
          return 'As mensagens selecionadas serão apagadas desta conversa.';
        }
        if (key === 'DELETE') return 'Apagar';
        if (key === 'CANCEL') return 'Cancelar';
      }

      if (key === 'COPIED') {
        return this.$t('CONVERSATION.MESSAGE_SELECTION.COPIED');
      }
      if (key === 'DELETED') {
        return this.$t('CONVERSATION.MESSAGE_SELECTION.DELETED');
      }
      if (key === 'FORWARDED') {
        return this.$t('CONVERSATION.MESSAGE_SELECTION.FORWARDED');
      }
      if (key === 'FORWARD_FAILED') {
        return this.$t('CONVERSATION.MESSAGE_SELECTION.FORWARD_FAILED');
      }
      if (key === 'NO_FORWARDABLE') {
        return this.$t('CONVERSATION.MESSAGE_SELECTION.NO_FORWARDABLE');
      }
      if (key === 'DELETE_TITLE') {
        return this.$t('CONVERSATION.MESSAGE_SELECTION.DELETE_TITLE');
      }
      if (key === 'DELETE_MESSAGE') {
        return this.$t('CONVERSATION.MESSAGE_SELECTION.DELETE_MESSAGE');
      }
      if (key === 'DELETE') {
        return this.$t('CONVERSATION.MESSAGE_SELECTION.DELETE');
      }

      return this.$t('CONVERSATION.MESSAGE_SELECTION.CANCEL');
    },
    toggleMessageSelection(message) {
      const messageId = message.id;
      if (!messageId) return;

      this.isMessageSelectionMode = true;
      if (this.selectedMessageIds.includes(messageId)) {
        this.selectedMessageIds = this.selectedMessageIds.filter(
          selectedId => selectedId !== messageId
        );
      } else {
        this.selectedMessageIds = [...this.selectedMessageIds, messageId];
      }

      if (!this.selectedMessageIds.length) {
        this.clearMessageSelection();
      }
    },
    clearMessageSelection() {
      this.isMessageSelectionMode = false;
      this.selectedMessageIds = [];
      this.showBulkDeleteModal = false;
      this.isForwardModalOpen = false;
    },
    async copySelectedMessages() {
      const text = this.selectedMessages
        .map(message => this.messageCopyText(message))
        .filter(Boolean)
        .join('\n\n');

      if (!text) {
        useAlert(this.messageSelectionText('NO_FORWARDABLE'));
        return;
      }

      await copyTextToClipboard(text);
      useAlert(this.messageSelectionText('COPIED'));
    },
    openBulkDeleteModal() {
      if (!this.selectedMessages.length) return;
      this.showBulkDeleteModal = true;
    },
    closeBulkDeleteModal() {
      if (this.isBulkDeleting) return;
      this.showBulkDeleteModal = false;
    },
    async confirmBulkDeletion() {
      if (!this.selectedMessages.length || this.isBulkDeleting) return;

      this.isBulkDeleting = true;
      try {
        await Promise.all(
          this.selectedMessages.map(message =>
            this.$store.dispatch('deleteMessage', {
              conversationId: this.currentChat.id,
              messageId: message.id,
            })
          )
        );
        useAlert(this.messageSelectionText('DELETED'));
        this.clearMessageSelection();
      } catch {
        useAlert(this.$t('CONVERSATION.FAIL_DELETE_MESSSAGE'));
      } finally {
        this.isBulkDeleting = false;
      }
    },
    openForwardModal() {
      if (!this.canForwardSelectedMessages) {
        useAlert(this.messageSelectionText('NO_FORWARDABLE'));
        return;
      }
      this.isForwardModalOpen = true;
    },
    async conversationIdForForwardTarget(target) {
      if (target.type === 'conversation') return target.conversationId;

      const response = await InboxesAPI.createWhatsmeowDirectConversation(
        this.inboxId,
        {
          participant_phone: target.phoneNumber,
          participant_name: target.label,
        }
      );
      return response.data?.conversation_id || response.data?.display_id;
    },
    async forwardSelectedMessages(targets) {
      if (!targets.length || this.isForwardingMessages) return;

      this.isForwardingMessages = true;
      try {
        const conversationIds = await Promise.all(
          targets.map(target => this.conversationIdForForwardTarget(target))
        );

        const validConversationIds = [
          ...new Set(conversationIds.filter(Boolean)),
        ];
        const sendTasks = validConversationIds.flatMap(conversationId =>
          this.forwardableSelectedMessages.map(message => ({
            conversationId,
            message,
          }))
        );

        await sendTasks.reduce((promise, { conversationId, message }) => {
          return promise.then(() =>
            this.forwardMessageToConversation(conversationId, message)
          );
        }, Promise.resolve());

        useAlert(this.messageSelectionText('FORWARDED'));
        this.clearMessageSelection();
      } catch (error) {
        useAlert(
          error?.response?.data?.message ||
            error?.response?.data?.error ||
            this.messageSelectionText('FORWARD_FAILED')
        );
      } finally {
        this.isForwardingMessages = false;
      }
    },
    toggleReplyEditorSize() {
      this.resizableEditorWrapperRef?.toggleEditorExpand?.();
    },
    resetReplyEditorHeight() {
      this.resizableEditorWrapperRef?.resetEditorHeight?.();
    },
  },
};
</script>

<template>
  <div
    ref="messagesViewRef"
    class="flex flex-col justify-between flex-grow h-full min-w-0 m-0"
  >
    <div ref="topBannerRef">
      <Banner
        v-if="!currentChat.can_reply"
        color-scheme="alert"
        class="mx-2 mt-2 overflow-hidden rounded-lg"
        :banner-message="replyWindowBannerMessage"
        :href-link="replyWindowLink"
        :href-link-text="replyWindowLinkText"
      />
      <Banner
        v-else-if="hasDuplicateInstagramInbox"
        color-scheme="alert"
        class="mx-2 mt-2 overflow-hidden rounded-lg"
        :banner-message="$t('CONVERSATION.OLD_INSTAGRAM_INBOX_REPLY_BANNER')"
      />
    </div>
    <MessageList
      ref="conversationPanelRef"
      class="conversation-panel flex-shrink flex-grow basis-px flex flex-col overflow-y-auto relative h-full m-0 pb-4"
      :current-user-id="currentUserId"
      :first-unread-id="unReadMessages[0]?.id"
      :is-an-email-channel="isAnEmailChannel"
      :inbox-supports-reply-to="inboxSupportsReplyTo"
      :is-selection-mode="isMessageSelectionMode"
      :messages="getMessages"
      :selected-message-ids="selectedMessageIds"
      @retry="handleMessageRetry"
      @select="toggleMessageSelection"
    >
      <template #beforeAll>
        <transition name="slide-up">
          <!-- eslint-disable-next-line vue/require-toggle-inside-transition -->
          <li
            class="min-h-[4rem] flex flex-shrink-0 flex-grow-0 items-center flex-auto justify-center max-w-full mt-0 mr-0 mb-1 ml-0 relative first:mt-auto last:mb-0"
          >
            <Spinner v-if="shouldShowSpinner" class="text-n-brand" />
          </li>
        </transition>
      </template>
      <template #unreadBadge>
        <li
          v-show="unreadMessageCount != 0"
          class="list-none flex justify-center items-center"
        >
          <span
            class="shadow-lg rounded-full bg-n-brand text-white text-xs font-medium my-2.5 mx-auto px-2.5 py-1.5"
          >
            {{ unreadMessageLabel }}
          </span>
        </li>
      </template>
      <template #after>
        <ConversationLabelSuggestion
          v-if="shouldShowLabelSuggestions"
          :suggested-labels="labelSuggestions"
          :chat-labels="currentChat.labels"
          :conversation-id="currentChat.id"
        />
      </template>
    </MessageList>
    <MessageSelectionToolbar
      v-if="isMessageSelectionMode"
      :selected-count="selectedMessageIds.length"
      :can-forward="canForwardSelectedMessages"
      :is-deleting="isBulkDeleting"
      :is-forwarding="isForwardingMessages"
      @clear="clearMessageSelection"
      @copy="copySelectedMessages"
      @delete="openBulkDeleteModal"
      @forward="openForwardModal"
    />
    <ForwardMessagesModal
      :is-open="isForwardModalOpen"
      :conversations="allConversations"
      :current-user-id="currentUserId"
      :selected-count="selectedMessageIds.length"
      :is-forwarding="isForwardingMessages"
      @close="isForwardModalOpen = false"
      @send="forwardSelectedMessages"
    />
    <Teleport to="body">
      <woot-delete-modal
        v-if="showBulkDeleteModal"
        v-model:show="showBulkDeleteModal"
        class="context-menu--delete-modal"
        :on-close="closeBulkDeleteModal"
        :on-confirm="confirmBulkDeletion"
        :title="messageSelectionText('DELETE_TITLE')"
        :message="messageSelectionText('DELETE_MESSAGE')"
        :confirm-text="messageSelectionText('DELETE')"
        :reject-text="messageSelectionText('CANCEL')"
      />
    </Teleport>
    <div
      class="flex relative flex-col bg-n-surface-1"
      :class="{ 'pb-14': isMessageSelectionMode }"
    >
      <div
        v-if="isAnyoneTyping"
        class="absolute flex items-center w-full h-0 -top-7"
      >
        <div
          class="flex py-2 pr-4 pl-5 shadow-md rounded-full bg-white dark:bg-n-solid-3 text-n-slate-11 text-xs font-semibold my-2.5 mx-auto"
        >
          {{ typingUserNames }}
          <img
            class="w-6 ltr:ml-2 rtl:mr-2"
            src="assets/images/typing.gif"
            alt="Someone is typing"
          />
        </div>
      </div>
      <ResizableEditorWrapper
        ref="resizableEditorWrapperRef"
        :container-height="Math.max(0, containerHeight - topBannerHeight)"
      >
        <ReplyBox @toggle-editor-size="toggleReplyEditorSize" />
      </ResizableEditorWrapper>
    </div>
  </div>
</template>
