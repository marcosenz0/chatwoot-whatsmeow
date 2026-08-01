<script setup>
import { computed } from 'vue';

import MessageMeta from '../MessageMeta.vue';
import CaptainGenerationDetails from '../CaptainGenerationDetails.vue';

import { emitter } from 'shared/helpers/mitt';
import { useMessageContext } from '../provider.js';
import { useI18n } from 'vue-i18n';

import MessageFormatter from 'shared/helpers/MessageFormatter.js';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { MESSAGE_VARIANTS, ORIENTATION, SENDER_TYPES } from '../constants';
import Icon from 'next/icon/Icon.vue';

const props = defineProps({
  hideMeta: { type: Boolean, default: false },
});

const {
  variant,
  orientation,
  inReplyTo,
  contentAttributes,
  shouldGroupWithNext,
  id,
  sender,
  senderType,
} = useMessageContext();
const { t } = useI18n();

const isCaptainMessage = computed(
  () =>
    (sender.value?.type ?? senderType.value) === SENDER_TYPES.CAPTAIN_ASSISTANT
);

const metaColorClass = computed(() =>
  variant.value === MESSAGE_VARIANTS.PRIVATE
    ? 'text-n-amber-12/50'
    : 'text-n-slate-11'
);

const emailMetaClass = computed(() =>
  variant.value === MESSAGE_VARIANTS.EMAIL ? 'px-3 pb-3' : ''
);

const varaintBaseMap = {
  [MESSAGE_VARIANTS.AGENT]: 'bg-n-solid-blue text-n-slate-12',
  [MESSAGE_VARIANTS.PRIVATE]:
    'bg-n-solid-amber text-n-amber-12 [&_.prosemirror-mention-node]:font-semibold',
  [MESSAGE_VARIANTS.USER]: 'bg-n-slate-4 text-n-slate-12',
  [MESSAGE_VARIANTS.ACTIVITY]: 'bg-n-alpha-1 text-n-slate-11 text-sm',
  [MESSAGE_VARIANTS.BOT]: 'bg-n-solid-iris text-n-slate-12',
  [MESSAGE_VARIANTS.TEMPLATE]: 'bg-n-solid-iris text-n-slate-12',
  [MESSAGE_VARIANTS.ERROR]: 'bg-n-ruby-4 text-n-ruby-12',
  [MESSAGE_VARIANTS.EMAIL]: 'w-full',
  [MESSAGE_VARIANTS.UNSUPPORTED]:
    'bg-n-solid-amber/70 border border-dashed border-n-amber-12 text-n-amber-12',
};

const orientationMap = {
  [ORIENTATION.LEFT]:
    'left-bubble rounded-xl ltr:rounded-bl-sm rtl:rounded-br-sm',
  [ORIENTATION.RIGHT]:
    'right-bubble rounded-xl ltr:rounded-br-sm rtl:rounded-bl-sm',
  [ORIENTATION.CENTER]: 'rounded-md',
};

const flexOrientationClass = computed(() => {
  const map = {
    [ORIENTATION.LEFT]: 'justify-start',
    [ORIENTATION.RIGHT]: 'justify-end',
    [ORIENTATION.CENTER]: 'justify-center',
  };

  return map[orientation.value];
});

const messageClass = computed(() => {
  const classToApply = [varaintBaseMap[variant.value]];

  if (variant.value !== MESSAGE_VARIANTS.ACTIVITY) {
    classToApply.push(orientationMap[orientation.value]);
  } else {
    classToApply.push('rounded-lg');
  }

  return classToApply;
});

const scrollToMessage = () => {
  if (!inReplyTo.value?.id) return;

  emitter.emit(BUS_EVENTS.SCROLL_TO_MESSAGE, {
    messageId: inReplyTo.value.id,
  });
};

const shouldShowMeta = computed(
  () =>
    !props.hideMeta &&
    !shouldGroupWithNext.value &&
    variant.value !== MESSAGE_VARIANTS.ACTIVITY
);

const isMessageDeleted = computed(() => !!contentAttributes.value?.deleted);
const isLocallyDeleted = computed(() => {
  const attributes = contentAttributes.value || {};
  const deletedBy = attributes.deletedBy || attributes.deleted_by;

  return !!attributes.deleted && !!deletedBy;
});

const deletedMessageLabel = computed(() =>
  isLocallyDeleted.value
    ? t('CONVERSATION.MESSAGE_DELETED_BY_ME')
    : t('CONVERSATION.MESSAGE_DELETED')
);

const deletedIndicatorClass = computed(() => {
  const classes = [
    'mt-2 flex items-center gap-1 text-[11px] font-medium leading-4 opacity-70',
  ];

  if (orientation.value === ORIENTATION.RIGHT) {
    classes.push('justify-end');
  } else {
    classes.push('justify-start');
  }

  return classes;
});

const quotedMessage = computed(
  () =>
    contentAttributes.value?.whatsmeowQuotedMessage ||
    contentAttributes.value?.whatsmeow_quoted_message
);

const fallbackReplyTo = computed(() => {
  if (!quotedMessage.value) return null;

  const fileType =
    quotedMessage.value.fileType || quotedMessage.value.file_type || null;

  return {
    content: quotedMessage.value.content || '',
    attachments: fileType ? [{ fileType }] : [],
  };
});

const replyToMessage = computed(() => inReplyTo.value || fallbackReplyTo.value);

const hasReplyToPreview = computed(() => !!replyToMessage.value);
const canScrollToReply = computed(() => !!inReplyTo.value?.id);

const replyToPreview = computed(() => {
  if (!replyToMessage.value) return '';

  const { content, attachments } = replyToMessage.value;

  if (content) return new MessageFormatter(content).formattedMessage;
  if (attachments?.length) {
    const firstAttachment = attachments[0];
    const fileType = firstAttachment.fileType ?? firstAttachment.file_type;

    return t(`CHAT_LIST.ATTACHMENTS.${fileType}.CONTENT`);
  }

  return t('CONVERSATION.REPLY_MESSAGE_NOT_FOUND');
});
</script>

<template>
  <div
    class="text-sm min-w-0"
    :class="[
      messageClass,
      {
        'max-w-lg': variant !== MESSAGE_VARIANTS.EMAIL,
      },
    ]"
  >
    <div
      v-if="hasReplyToPreview"
      class="p-2 -mx-1 mb-2 rounded-lg bg-n-alpha-black1"
      :class="{ 'cursor-pointer': canScrollToReply }"
      @click="scrollToMessage"
    >
      <div
        v-dompurify-html="replyToPreview"
        class="prose prose-bubble line-clamp-2"
      />
    </div>
    <slot />
    <div v-if="isMessageDeleted" :class="deletedIndicatorClass">
      <Icon icon="i-lucide-ban" class="size-3 shrink-0" />
      <span>{{ deletedMessageLabel }}</span>
    </div>
    <template v-if="shouldShowMeta">
      <CaptainGenerationDetails
        v-if="isCaptainMessage"
        :message-id="id"
        class="mt-2"
      >
        <template #meta>
          <MessageMeta :class="[emailMetaClass, metaColorClass]" />
        </template>
      </CaptainGenerationDetails>
      <MessageMeta
        v-else
        :class="[flexOrientationClass, emailMetaClass, metaColorClass]"
        class="mt-2"
      />
    </template>
  </div>
</template>
