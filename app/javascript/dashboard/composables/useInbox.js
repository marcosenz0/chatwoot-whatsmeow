import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useCamelCase } from 'dashboard/composables/useTransformKeys';
import {
  INBOX_TYPES,
  isVoiceCallEnabled,
  getVoiceCallProvider,
} from 'dashboard/helper/inbox';

export const INBOX_FEATURES = {
  REPLY_TO: 'replyTo',
  REPLY_TO_OUTGOING: 'replyToOutgoing',
};

// This is a single source of truth for inbox features
// This is used to check if a feature is available for a particular inbox or not
export const INBOX_FEATURE_MAP = {
  [INBOX_FEATURES.REPLY_TO]: [
    INBOX_TYPES.FB,
    INBOX_TYPES.WEB,
    INBOX_TYPES.TWITTER,
    INBOX_TYPES.WHATSAPP,
    INBOX_TYPES.WHATSMEOW,
    INBOX_TYPES.TELEGRAM,
    INBOX_TYPES.TELEGRAM_PERSONAL,
    INBOX_TYPES.TIKTOK,
    INBOX_TYPES.API,
  ],
  [INBOX_FEATURES.REPLY_TO_OUTGOING]: [
    INBOX_TYPES.WEB,
    INBOX_TYPES.TWITTER,
    INBOX_TYPES.WHATSAPP,
    INBOX_TYPES.WHATSMEOW,
    INBOX_TYPES.TELEGRAM,
    INBOX_TYPES.TELEGRAM_PERSONAL,
    INBOX_TYPES.TIKTOK,
    INBOX_TYPES.API,
  ],
};

/**
 * Composable for handling inbox-related functionality
 * @param {string|null} inboxId - Optional inbox ID. If not provided, uses current chat's inbox
 * @returns {Object} An object containing inbox type checking functions
 */
export const useInbox = (inboxId = null) => {
  const currentChat = useMapGetter('getSelectedChat');
  const inboxGetter = useMapGetter('inboxes/getInboxById');

  const inbox = computed(() => {
    const targetInboxId = inboxId || currentChat.value?.inbox_id;

    if (!targetInboxId) return null;

    return useCamelCase(inboxGetter.value(targetInboxId), { deep: true });
  });

  const channelType = computed(() => inbox.value?.channelType);

  const isAPIInbox = computed(() => channelType.value === INBOX_TYPES.API);

  const isAFacebookInbox = computed(() => channelType.value === INBOX_TYPES.FB);

  const isAWebWidgetInbox = computed(
    () => channelType.value === INBOX_TYPES.WEB
  );

  const isATwilioChannel = computed(
    () => channelType.value === INBOX_TYPES.TWILIO
  );

  const isALineChannel = computed(() => channelType.value === INBOX_TYPES.LINE);

  const isAnEmailChannel = computed(
    () => channelType.value === INBOX_TYPES.EMAIL
  );

  const isATelegramChannel = computed(() =>
    [INBOX_TYPES.TELEGRAM, INBOX_TYPES.TELEGRAM_PERSONAL].includes(
      channelType.value
    )
  );

  const isATelegramPersonalChannel = computed(
    () => channelType.value === INBOX_TYPES.TELEGRAM_PERSONAL
  );

  const whatsAppAPIProvider = computed(() => inbox.value?.provider || '');

  const isAMicrosoftInbox = computed(
    () => isAnEmailChannel.value && inbox.value?.provider === 'microsoft'
  );

  const isAGoogleInbox = computed(
    () => isAnEmailChannel.value && inbox.value?.provider === 'google'
  );

  const isATwilioSMSChannel = computed(() => {
    const { medium = '' } = inbox.value || {};
    return isATwilioChannel.value && medium === 'sms';
  });

  const isASmsInbox = computed(
    () => channelType.value === INBOX_TYPES.SMS || isATwilioSMSChannel.value
  );

  const isATwilioWhatsAppChannel = computed(() => {
    const { medium = '' } = inbox.value || {};
    return isATwilioChannel.value && medium === 'whatsapp';
  });

  const isAWhatsAppCloudChannel = computed(
    () =>
      channelType.value === INBOX_TYPES.WHATSAPP &&
      whatsAppAPIProvider.value === 'whatsapp_cloud'
  );

  const is360DialogWhatsAppChannel = computed(
    () =>
      channelType.value === INBOX_TYPES.WHATSAPP &&
      whatsAppAPIProvider.value === 'default'
  );

  const isAWhatsAppChannel = computed(
    () =>
      channelType.value === INBOX_TYPES.WHATSAPP ||
      channelType.value === INBOX_TYPES.WHATSMEOW ||
      isATwilioWhatsAppChannel.value
  );

  const isAnInstagramChannel = computed(
    () => channelType.value === INBOX_TYPES.INSTAGRAM
  );

  const isATiktokChannel = computed(
    () => channelType.value === INBOX_TYPES.TIKTOK
  );

  const voiceCallEnabled = computed(() => isVoiceCallEnabled(inbox.value));

  const voiceCallProvider = computed(() => getVoiceCallProvider(inbox.value));

  return {
    inbox,
    isAFacebookInbox,
    isALineChannel,
    isAPIInbox,
    isASmsInbox,
    isATelegramChannel,
    isATelegramPersonalChannel,
    isATwilioChannel,
    isATwilioSMSChannel,
    isAWebWidgetInbox,
    isAWhatsAppChannel,
    isAMicrosoftInbox,
    isAGoogleInbox,
    isATwilioWhatsAppChannel,
    isAWhatsAppCloudChannel,
    is360DialogWhatsAppChannel,
    isAnEmailChannel,
    isAnInstagramChannel,
    isATiktokChannel,
    voiceCallEnabled,
    voiceCallProvider,
  };
};
