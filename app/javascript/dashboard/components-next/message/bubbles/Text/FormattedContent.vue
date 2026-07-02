<script setup>
import { computed, ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useMessageContext } from '../../provider.js';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import WhatsmeowGroupInviteModal from './WhatsmeowGroupInviteModal.vue';

import MessageFormatter from 'shared/helpers/MessageFormatter.js';
import { MESSAGE_VARIANTS } from '../../constants';
import InboxesAPI from 'dashboard/api/inboxes';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import {
  linkifyWhatsmeowGroupInvites,
  whatsmeowGroupInviteElementFromTarget,
} from 'dashboard/helper/whatsmeowGroupInviteHelper';
import {
  linkifyWhatsmeowPhoneNumbers,
  normalizeWhatsmeowPhoneNumber,
  whatsmeowPhoneElementFromTarget,
} from 'dashboard/helper/whatsmeowPhoneNumberHelper';
import {
  whatsmeowConversationPath,
  whatsmeowDirectConversationPayload,
} from 'dashboard/helper/whatsmeowConversationHelper';

const props = defineProps({
  content: {
    type: String,
    required: true,
  },
});

const PHONE_MENU_WIDTH = 272;
const phoneCheckCache = new Map();
const groupInvitePreviewCache = new Map();

const { variant, inboxId } = useMessageContext();
const inboxGetter = useMapGetter('inboxes/getInbox');
const inbox = computed(() => inboxGetter.value(inboxId.value) || {});
const route = useRoute();
const router = useRouter();
const { t } = useI18n();

const phoneMenu = ref(null);
const phoneMenuStyle = ref({});
const isOpeningConversation = ref(false);
const groupInviteModal = ref(null);
const groupInviteError = ref('');
const isLoadingGroupInvite = ref(false);
const isJoiningGroupInvite = ref(false);

const isWhatsmeowInbox = computed(
  () =>
    inbox.value.channel_type === 'Channel::Whatsmeow' ||
    inbox.value.channelType === 'Channel::Whatsmeow'
);

const renderedContent = computed(() => {
  if (variant.value === MESSAGE_VARIANTS.ACTIVITY) {
    return props.content;
  }

  return new MessageFormatter(props.content).formattedMessage;
});

const formattedContent = computed(() => {
  if (!isWhatsmeowInbox.value || variant.value === MESSAGE_VARIANTS.ACTIVITY) {
    return renderedContent.value;
  }

  return linkifyWhatsmeowGroupInvites(
    linkifyWhatsmeowPhoneNumbers(renderedContent.value)
  );
});

const isPhoneMenuOpen = computed(() => !!phoneMenu.value);
const isGroupInviteModalOpen = computed(() => !!groupInviteModal.value);

const phoneLabel = computed(
  () =>
    phoneMenu.value?.phoneNumber ||
    phoneMenu.value?.normalizedNumber ||
    phoneMenu.value?.rawNumber ||
    ''
);

const canOpenConversation = computed(
  () =>
    !!phoneMenu.value?.isOnWhatsApp &&
    !phoneMenu.value?.isChecking &&
    !isOpeningConversation.value
);

const closePhoneMenu = () => {
  phoneMenu.value = null;
  isOpeningConversation.value = false;
};

const closeGroupInviteModal = () => {
  groupInviteModal.value = null;
  groupInviteError.value = '';
  isLoadingGroupInvite.value = false;
  isJoiningGroupInvite.value = false;
};

const positionPhoneMenu = element => {
  const rect = element.getBoundingClientRect();
  const viewportWidth = window.innerWidth || PHONE_MENU_WIDTH;
  const left = Math.min(
    Math.max(rect.left, 8),
    Math.max(viewportWidth - PHONE_MENU_WIDTH - 8, 8)
  );

  phoneMenuStyle.value = {
    left: `${left}px`,
    top: `${rect.bottom + 8}px`,
  };
};

const applyPhoneCheckResult = (rawNumber, result) => {
  if (!phoneMenu.value || phoneMenu.value.rawNumber !== rawNumber) return;

  phoneMenu.value = {
    ...phoneMenu.value,
    isChecking: false,
    isOnWhatsApp: !!(result.is_on_whatsapp || result.isOnWhatsApp),
    jid: result.jid || '',
    phoneNumber:
      result.phone ||
      phoneMenu.value.normalizedNumber ||
      phoneMenu.value.rawNumber,
  };
};

const checkPhoneNumber = async rawNumber => {
  const normalizedNumber =
    phoneMenu.value?.normalizedNumber ||
    normalizeWhatsmeowPhoneNumber(rawNumber);
  const cacheKey = normalizedNumber || rawNumber;

  if (phoneCheckCache.has(cacheKey)) {
    applyPhoneCheckResult(rawNumber, phoneCheckCache.get(cacheKey));
    return;
  }

  try {
    const { data } = await InboxesAPI.checkWhatsmeowNumber(
      inboxId.value,
      normalizedNumber || rawNumber
    );
    phoneCheckCache.set(cacheKey, data);
    applyPhoneCheckResult(rawNumber, data);
  } catch {
    applyPhoneCheckResult(rawNumber, {
      is_on_whatsapp: false,
      phone: normalizedNumber || rawNumber,
    });
  }
};

const openPhoneMenu = element => {
  const rawNumber = element.dataset.whatsmeowPhoneNumber;
  const normalizedNumber =
    element.dataset.whatsmeowPhoneNormalized ||
    normalizeWhatsmeowPhoneNumber(rawNumber);

  if (!rawNumber) return;

  positionPhoneMenu(element);
  phoneMenu.value = {
    rawNumber,
    normalizedNumber,
    phoneNumber: normalizedNumber || rawNumber,
    jid: '',
    isChecking: true,
    isOnWhatsApp: false,
  };
  checkPhoneNumber(rawNumber);
};

const handlePhoneClick = event => {
  const element = whatsmeowPhoneElementFromTarget(event.target);
  if (!element) return;

  event.preventDefault();
  event.stopPropagation();
  openPhoneMenu(element);
};

const handlePhoneKeydown = event => {
  if (!['Enter', ' '].includes(event.key)) return;

  const element = whatsmeowPhoneElementFromTarget(event.target);
  if (!element) return;

  event.preventDefault();
  event.stopPropagation();
  openPhoneMenu(element);
};

const applyGroupInvitePreview = (code, data) => {
  if (!groupInviteModal.value || groupInviteModal.value.code !== code) return;

  groupInviteModal.value = {
    ...groupInviteModal.value,
    ...data,
  };
  groupInviteError.value = '';
  isLoadingGroupInvite.value = false;
};

const loadGroupInvitePreview = async ({ code, url }) => {
  if (groupInvitePreviewCache.has(code)) {
    applyGroupInvitePreview(code, groupInvitePreviewCache.get(code));
    return;
  }

  isLoadingGroupInvite.value = true;
  groupInviteError.value = '';
  try {
    const { data } = await InboxesAPI.getWhatsmeowGroupInvite(inboxId.value, {
      code,
      url,
    });
    groupInvitePreviewCache.set(code, data);
    applyGroupInvitePreview(code, data);
  } catch (error) {
    if (!groupInviteModal.value || groupInviteModal.value.code !== code) return;

    groupInviteError.value =
      error?.response?.data?.message ||
      t('CONVERSATION.WHATSMEOW_GROUP_INVITE.LOAD_FAILED');
    isLoadingGroupInvite.value = false;
  }
};

const openGroupInviteModal = element => {
  const code = element.dataset.whatsmeowGroupInviteCode;
  const url = element.dataset.whatsmeowGroupInviteUrl || element.href || '';
  if (!code) return;

  closePhoneMenu();
  groupInviteModal.value = { code, link: url };
  loadGroupInvitePreview({ code, url });
};

const handleGroupInviteClick = event => {
  const element = whatsmeowGroupInviteElementFromTarget(event.target);
  if (!element) return false;

  event.preventDefault();
  event.stopPropagation();
  openGroupInviteModal(element);
  return true;
};

const handleGroupInviteKeydown = event => {
  if (!['Enter', ' '].includes(event.key)) return false;

  const element = whatsmeowGroupInviteElementFromTarget(event.target);
  if (!element) return false;

  event.preventDefault();
  event.stopPropagation();
  openGroupInviteModal(element);
  return true;
};

const handleContentClick = event => {
  if (handleGroupInviteClick(event)) return;

  handlePhoneClick(event);
};

const handleContentKeydown = event => {
  if (handleGroupInviteKeydown(event)) return;

  handlePhoneKeydown(event);
};

const copyPhoneNumber = async () => {
  if (!phoneLabel.value) return;

  await copyTextToClipboard(phoneLabel.value);
  useAlert(t('CONVERSATION.WHATSMEOW_PHONE.COPIED'));
  closePhoneMenu();
};

const openPhoneConversation = async () => {
  if (!canOpenConversation.value) return;

  isOpeningConversation.value = true;
  try {
    const { data } = await InboxesAPI.createWhatsmeowDirectConversation(
      inboxId.value,
      whatsmeowDirectConversationPayload({
        jid: phoneMenu.value.jid,
        phoneNumber: phoneMenu.value.phoneNumber,
        name: phoneMenu.value.phoneNumber,
      })
    );
    const conversationId = data.conversation_id || data.id;
    await router.push({
      path: whatsmeowConversationPath({
        route,
        inboxId: inboxId.value,
        conversationId,
      }),
    });
  } catch (error) {
    useAlert(
      error?.response?.data?.message ||
        t('CONVERSATION.WHATSMEOW_PHONE.OPEN_FAILED')
    );
  } finally {
    closePhoneMenu();
  }
};

const joinGroupInvite = async () => {
  const code = groupInviteModal.value?.code;
  if (!code || isJoiningGroupInvite.value) return;

  isJoiningGroupInvite.value = true;
  groupInviteError.value = '';
  try {
    const { data } = await InboxesAPI.joinWhatsmeowGroupInvite(inboxId.value, {
      code,
    });
    groupInvitePreviewCache.set(code, data);
    const conversationId = data.conversation_id || data.id;
    useAlert(
      data.pending_approval
        ? t('CONVERSATION.WHATSMEOW_GROUP_INVITE.REQUEST_SENT')
        : t('CONVERSATION.WHATSMEOW_GROUP_INVITE.JOINED')
    );
    closeGroupInviteModal();
    if (conversationId) {
      await router.push({
        path: whatsmeowConversationPath({
          route,
          inboxId: inboxId.value,
          conversationId,
        }),
      });
    }
  } catch (error) {
    groupInviteError.value =
      error?.response?.data?.message ||
      t('CONVERSATION.WHATSMEOW_GROUP_INVITE.JOIN_FAILED');
    useAlert(groupInviteError.value);
  } finally {
    isJoiningGroupInvite.value = false;
  }
};
</script>

<template>
  <span v-on-clickaway="closePhoneMenu" class="relative inline">
    <span
      v-dompurify-html="formattedContent"
      class="prose prose-bubble"
      @click="handleContentClick"
      @keydown="handleContentKeydown"
    />
    <div
      v-if="isPhoneMenuOpen"
      class="fixed z-[70] w-[17rem] rounded-lg border border-n-weak bg-n-alpha-3 p-2 shadow-lg backdrop-blur-[100px]"
      :style="phoneMenuStyle"
      @click.stop
      @contextmenu.stop
    >
      <div class="flex flex-col gap-1">
        <button
          v-if="phoneMenu.isChecking"
          type="button"
          class="flex w-full items-center gap-3 rounded-md px-3 py-2 text-left text-sm font-medium text-n-slate-11"
          disabled
        >
          <span class="i-lucide-loader-circle size-4 shrink-0 animate-spin" />
          <span>{{ $t('CONVERSATION.WHATSMEOW_PHONE.CHECKING') }}</span>
        </button>
        <button
          v-if="canOpenConversation"
          type="button"
          class="flex w-full items-center gap-3 rounded-md px-3 py-2 text-left text-sm font-medium text-n-slate-12 hover:bg-n-alpha-2"
          :disabled="isOpeningConversation"
          @click="openPhoneConversation"
        >
          <span
            class="size-4 shrink-0"
            :class="
              isOpeningConversation
                ? 'i-lucide-loader-circle animate-spin'
                : 'i-ph-chat-circle-dots'
            "
          />
          <span>
            {{
              $t('CONVERSATION.WHATSMEOW_PHONE.CHAT_WITH', {
                phone: phoneLabel,
              })
            }}
          </span>
        </button>
        <button
          type="button"
          class="flex w-full items-center gap-3 rounded-md px-3 py-2 text-left text-sm font-medium text-n-slate-12 hover:bg-n-alpha-2"
          @click="copyPhoneNumber"
        >
          <span class="i-lucide-copy size-4 shrink-0" />
          <span>{{ $t('CONVERSATION.WHATSMEOW_PHONE.COPY_PHONE') }}</span>
        </button>
      </div>
    </div>
    <WhatsmeowGroupInviteModal
      :is-open="isGroupInviteModalOpen"
      :invite="groupInviteModal || {}"
      :is-loading="isLoadingGroupInvite"
      :is-joining="isJoiningGroupInvite"
      :error="groupInviteError"
      @close="closeGroupInviteModal"
      @join="joinGroupInvite"
    />
  </span>
</template>
