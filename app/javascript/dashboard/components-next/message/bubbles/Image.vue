<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useLoadWithRetry } from 'dashboard/composables/loadWithRetry';
import BaseBubble from './Base.vue';
import Button from 'next/button/Button.vue';
import Icon from 'next/icon/Icon.vue';
import { useSnakeCase } from 'dashboard/composables/useTransformKeys';
import { useMessageContext } from '../provider.js';
import { downloadFile } from '@chatwoot/utils';

import GalleryView from 'dashboard/components/widgets/conversation/components/GalleryView.vue';

const { t } = useI18n();

const {
  filteredCurrentChatAttachments,
  attachments,
  mediaGroup,
  id,
  conversationId,
  forwardMediaMessage,
} = useMessageContext();

const attachment = computed(() => {
  return attachments.value[0];
});

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
  <BaseBubble
    class="max-w-[20rem] overflow-hidden p-1.5"
    data-bubble-name="image"
    @click="openGallery(attachment)"
  >
    <div v-if="hasError" class="flex items-center gap-1 text-center rounded-lg">
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
          groupedImages.length === 3 && index === 0 ? 'col-span-2 h-40' : 'h-36'
        "
        @click.stop="openGallery(item)"
      >
        <img
          :src="item.thumbUrl || item.dataUrl"
          class="size-full object-cover transition hover:scale-105"
        />
        <span
          v-if="index === 3 && groupedImages.length > 4"
          class="absolute inset-0 grid place-content-center bg-black/60 text-xl font-semibold text-white"
        >
          {{ `+${groupedImages.length - 4}` }}
        </span>
      </button>
    </div>
    <div v-else-if="isLoaded" class="relative group rounded-lg overflow-hidden">
      <img
        class="skip-context-menu max-h-80 max-w-full rounded-lg object-contain"
        :src="attachment.dataUrl"
        :width="attachment.width"
        :height="attachment.height"
      />
      <div
        class="inset-0 p-2 pointer-events-none absolute bg-gradient-to-tl from-n-slate-12/30 dark:from-n-slate-1/50 via-transparent to-transparent hidden group-hover:flex"
      />
      <div class="absolute right-2 bottom-2 hidden group-hover:flex gap-2">
        <Button xs solid slate icon="i-lucide-expand" class="opacity-60" />
        <Button
          xs
          solid
          slate
          icon="i-lucide-download"
          class="opacity-60"
          :is-loading="isDownloading"
          :disabled="isDownloading"
          @click.stop="downloadAttachment"
        />
      </div>
    </div>
  </BaseBubble>
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
