<script setup>
import { computed, ref, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';
import Button from 'next/button/Button.vue';
import { useSnakeCase } from 'dashboard/composables/useTransformKeys';
import GalleryView from 'dashboard/components/widgets/conversation/components/GalleryView.vue';
import { useMessageContext } from '../provider.js';
import VideoPlayer from '../VideoPlayer.vue';
import TextBubble from './Text/Index.vue';
import { ATTACHMENT_TYPES } from '../constants';

const { t } = useI18n();
const showGallery = ref(false);
const player = useTemplateRef('player');
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

const openGallery = () => {
  player.value.pause();
  showGallery.value = true;
};
</script>

<template>
  <TextBubble bubble-name="video" class="w-72 !max-w-full">
    <template #media>
      <VideoPlayer
        v-if="attachment.dataUrl"
        :key="attachment.dataUrl"
        ref="player"
        :src="attachment.dataUrl"
        :poster="attachment.thumbUrl"
        class="mx-auto"
      >
        <Icon
          v-if="isReel"
          icon="i-lucide-instagram"
          class="pointer-events-none absolute left-2 top-2 size-4 text-white"
        />
        <Button
          :aria-label="t('GALLERY_VIEW.EXPAND')"
          :title="t('GALLERY_VIEW.EXPAND')"
          icon="i-lucide-expand"
          slate
          solid
          xs
          class="absolute right-2 top-2 opacity-80"
          @click.stop="openGallery"
        />
      </VideoPlayer>
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
    @forward="forwardMediaMessage"
    @close="showGallery = false"
  />
</template>
