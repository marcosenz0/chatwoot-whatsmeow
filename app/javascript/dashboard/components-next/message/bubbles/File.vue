<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import FileIcon from 'next/icon/FileIcon.vue';
import { useSnakeCase } from 'dashboard/composables/useTransformKeys';
import {
  attachmentFileName,
  isPdfAttachment,
} from 'dashboard/helper/pdfAttachmentHelper';
import PdfViewer from 'dashboard/components/widgets/conversation/components/PdfViewer.vue';
import BaseAttachmentBubble from './BaseAttachment.vue';
import { useMessageContext } from '../provider.js';

const {
  attachments,
  id,
  conversationId,
  sender,
  createdAt,
  isPreview,
  forwardMediaMessage,
} = useMessageContext();
const showPdf = ref(false);
const attachment = computed(() => attachments.value[0]);
const pdfAttachment = computed(() => ({
  ...useSnakeCase(attachment.value),
  message_id: id.value,
  sender: sender.value,
  created_at: createdAt.value,
}));

const { t } = useI18n();

const url = computed(() => attachments.value[0].dataUrl);
const isPdf = computed(() => !!url.value && isPdfAttachment(attachment.value));

const fileName = computed(() => {
  if (url.value) {
    const filename = attachmentFileName(attachment.value);
    return filename || t('CONVERSATION.UNKNOWN_FILE_TYPE');
  }
  return t('CONVERSATION.UNKNOWN_FILE_TYPE');
});

const fileType = computed(() => fileName.value.split('.').pop());
</script>

<template>
  <BaseAttachmentBubble
    icon="i-teenyicons-user-circle-solid"
    icon-bg-color="bg-n-alpha-3 dark:bg-n-alpha-white"
    sender-translation-key="CONVERSATION.SHARED_ATTACHMENT.FILE"
    :content="fileName"
    :action="{
      href: url,
      label: $t('CONVERSATION.DOWNLOAD'),
    }"
  >
    <template #icon>
      <FileIcon :file-type="fileType" class="size-4" />
    </template>
    <template v-if="isPdf" #actions>
      <div class="flex gap-2">
        <button
          type="button"
          class="flex-1 rounded-lg border border-n-container bg-n-solid-3 px-4 py-2 text-center text-sm hover:bg-n-alpha-2"
          @click.stop="showPdf = true"
        >
          {{ t('PDF_VIEWER.VIEW') }}
        </button>
        <a
          :href="url"
          target="_blank"
          rel="noreferrer noopener nofollow"
          class="flex-1 rounded-lg border border-n-container bg-n-solid-3 px-4 py-2 text-center text-sm hover:bg-n-alpha-2"
          @click.stop
        >
          {{ t('CONVERSATION.DOWNLOAD') }}
        </a>
      </div>
    </template>
  </BaseAttachmentBubble>
  <PdfViewer
    v-if="showPdf"
    v-model:show="showPdf"
    :attachment="pdfAttachment"
    :conversation-id="conversationId"
    :allow-forward="!isPreview"
    @forward="forwardMediaMessage"
    @close="showPdf = false"
  />
</template>
