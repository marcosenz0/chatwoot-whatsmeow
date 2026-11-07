<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useLoadWithRetry } from 'dashboard/composables/loadWithRetry';
import Button from 'next/button/Button.vue';
import Icon from 'next/icon/Icon.vue';
import { useSnakeCase } from 'dashboard/composables/useTransformKeys';
import { messageTimestamp } from 'shared/helpers/timeHelper';
import { downloadFile } from '@chatwoot/utils';

import GalleryView from 'dashboard/components/widgets/conversation/components/GalleryView.vue';
import { useMessageContext } from '../provider.js';
import TextBubble from './Text/Index.vue';

const { t } = useI18n();

const {
  filteredCurrentChatAttachments,
  attachments,
  mediaGroup,
  id,
  conversationId,
  forwardMediaMessage,
} = useMessageContext();

const attachment = computed(() => attachments.value[0]);

const { isLoaded, hasError, loadWithRetry } = useLoadWithRetry();

const showGallery = ref(false);
const selectedGalleryAttachment = ref(null);
const isDownloading = ref(false);

const galleryAttachment = computed(
  () => selectedGalleryAttachment.value || attachment.value
);
const groupedImages = computed(() =>
  mediaGroup.value.length > 1
    ? mediaGroup.value
    : attachments.value
        .filter(item => item.fileType === 'image')
        .map(item => ({ ...item, messageId: id.value }))
);
const galleryAttachments = computed(() =>
  groupedImages.value.length > 1
    ? useSnakeCase(groupedImages.value)
    : filteredCurrentChatAttachments.value
);

const openGallery = item => {
  selectedGalleryAttachment.value = item;
  showGallery.value = true;
};

onMounted(() => {
  if (attachment.value?.dataUrl) {
    loadWithRetry(attachment.value.dataUrl);
  }
});

const downloadAttachment = async () => {
  const { fileType, dataUrl, extension } = attachment.value;
  try {
    isDownloading.value = true;
    await downloadFile({ url: dataUrl, type: fileType, extension });
  } catch (error) {
    useAlert(t('GALLERY_VIEW.ERROR_DOWNLOADING'));
  } finally {
    isDownloading.value = false;
  }
};

const handleImageError = () => {
  hasError.value = true;
};
</script>

<template>
  <TextBubble bubble-name="image" class="w-72 !max-w-full">
    <template #media>
      <div
        v-if="hasError"
        class="flex items-center gap-1 text-center rounded-lg"
      >
        <Icon icon="i-lucide-circle-off" class="text-n-slate-11" />
        <p class="mb-0 text-n-slate-11">
          {{ $t('COMPONENTS.MEDIA.IMAGE_UNAVAILABLE') }}
        </p>
      </div>
      <div
        v-else-if="isLoaded && groupedImages.length > 1"
        class="grid max-w-80 grid-cols-2 gap-0.5 overflow-hidden rounded-lg"
      >
        <button
          v-for="(item, index) in groupedImages.slice(0, 4)"
          :key="item.id || item.messageId"
          type="button"
          class="relative overflow-hidden bg-n-alpha-2"
          :class="
            groupedImages.length === 3 && index === 0
              ? 'col-span-2 h-40'
              : 'h-36'
          "
          :aria-label="t('GALLERY_VIEW.EXPAND')"
          @click.stop="openGallery(item)"
        >
          <img
            :src="item.thumbUrl || item.dataUrl"
            alt=""
            class="size-full object-cover transition hover:scale-105"
          />
          <span
            v-if="index === 3 && groupedImages.length > 4"
            class="absolute inset-0 grid place-content-center bg-black/60 text-xl font-semibold text-white"
          >
            {{ `+${groupedImages.length - 4}` }}
          </span>
          <time
            v-if="item.createdAt"
            class="pointer-events-none absolute inset-x-0 bottom-0 bg-gradient-to-t from-black/80 to-transparent px-1.5 pb-1 pt-2 text-end text-[10px] tabular-nums text-white"
          >
            {{ messageTimestamp(item.createdAt, 'LLL d, h:mm a') }}
          </time>
        </button>
      </div>
      <div
        v-else-if="isLoaded"
        class="relative group rounded-lg overflow-hidden"
      >
        <button
          type="button"
          :aria-label="t('GALLERY_VIEW.EXPAND')"
          class="block w-full cursor-zoom-in rounded-lg focus-visible:outline focus-visible:-outline-offset-2"
          @click.stop="openGallery(attachment)"
        >
          <img
            class="skip-context-menu mx-auto h-auto max-h-[22rem] w-full rounded-lg object-contain"
            :src="attachment.dataUrl"
            :width="attachment.width"
            :height="attachment.height"
            alt=""
          />
        </button>
        <div
          class="inset-0 p-2 pointer-events-none absolute bg-gradient-to-tl from-n-slate-12/30 dark:from-n-slate-1/50 via-transparent to-transparent hidden group-hover:flex"
        />
        <div
          class="absolute right-2 bottom-2 hidden group-hover:flex group-focus-within:flex gap-2"
        >
          <Button
            xs
            solid
            slate
            icon="i-lucide-download"
            class="opacity-60"
            :aria-label="t('CONVERSATION.DOWNLOAD')"
            :title="t('CONVERSATION.DOWNLOAD')"
            :is-loading="isDownloading"
            :disabled="isDownloading"
            @click.stop="downloadAttachment"
          />
        </div>
      </div>
      <div
        v-else
        class="aspect-square max-h-72 animate-pulse rounded-lg bg-n-alpha-2"
      />
    </template>
  </TextBubble>
  <GalleryView
    v-if="showGallery"
    v-model:show="showGallery"
    :attachment="useSnakeCase(galleryAttachment)"
    :all-attachments="galleryAttachments"
    :conversation-id="conversationId"
    @forward="forwardMediaMessage"
    @error="handleImageError"
    @close="() => (showGallery = false)"
  />
</template>
