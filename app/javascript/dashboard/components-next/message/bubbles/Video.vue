<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';
import { useSnakeCase } from 'dashboard/composables/useTransformKeys';
import GalleryView from 'dashboard/components/widgets/conversation/components/GalleryView.vue';
import { useMessageContext } from '../provider.js';
import TextBubble from './Text/Index.vue';
import { ATTACHMENT_TYPES } from '../constants';

const { t } = useI18n();
const showGallery = ref(false);
const hasPreviewError = ref(false);
const {
  filteredCurrentChatAttachments,
  attachments,
  conversationId,
  forwardMediaMessage,
} = useMessageContext();

const attachment = computed(() => attachments.value[0]);

const isReel = computed(
  () => attachment.value.fileType === ATTACHMENT_TYPES.IG_REEL
);
</script>

<template>
  <TextBubble bubble-name="video" class="w-72 !max-w-full">
    <template #media>
      <button
        v-if="attachment.dataUrl && !hasPreviewError"
        type="button"
        :aria-label="t('GALLERY_VIEW.EXPAND')"
        class="relative mx-auto block max-w-full cursor-pointer overflow-hidden rounded-lg bg-black text-white focus-visible:outline focus-visible:outline-white"
        @click.stop="showGallery = true"
      >
        <video
          :src="attachment.dataUrl"
          :poster="attachment.thumbUrl || undefined"
          class="skip-context-menu pointer-events-none block h-auto max-h-[22rem] max-w-full object-contain"
          aria-hidden="true"
          preload="metadata"
          muted
          playsinline
          @error="hasPreviewError = true"
        />
        <Icon
          v-if="isReel"
          icon="i-lucide-instagram"
          class="pointer-events-none absolute left-2 top-2 size-4"
        />
        <span
          class="pointer-events-none absolute left-1/2 top-1/2 grid size-11 -translate-x-1/2 -translate-y-1/2 place-items-center rounded-full bg-black/60"
        >
          <Icon icon="i-lucide-play" class="size-5 fill-current" />
        </span>
      </button>
      <div v-else class="flex items-center gap-2 p-5 text-sm text-n-slate-11">
        <Icon icon="i-lucide-circle-off" />
        {{ t('GALLERY_VIEW.MEDIA_UNAVAILABLE') }}
      </div>
    </template>
  </TextBubble>
  <GalleryView
    v-if="showGallery"
    v-model:show="showGallery"
    :attachment="useSnakeCase(attachment)"
    :all-attachments="filteredCurrentChatAttachments"
    :conversation-id="conversationId"
    auto-play
    @forward="forwardMediaMessage"
    @close="showGallery = false"
  />
</template>
