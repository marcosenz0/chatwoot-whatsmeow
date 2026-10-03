<script setup>
import { ref, computed } from 'vue';
import Icon from 'next/icon/Icon.vue';
import Button from 'next/button/Button.vue';
import { useI18n } from 'vue-i18n';
import { useSnakeCase } from 'dashboard/composables/useTransformKeys';
import GalleryView from 'dashboard/components/widgets/conversation/components/GalleryView.vue';
import { useMessageContext } from '../provider.js';
import BaseBubble from './Base.vue';
import { ATTACHMENT_TYPES } from '../constants';

const emit = defineEmits(['error']);
const { t } = useI18n();
const hasError = ref(false);
const showGallery = ref(false);
const {
  filteredCurrentChatAttachments,
  attachments,
  conversationId,
  forwardMediaMessage,
} = useMessageContext();

const handleError = () => {
  hasError.value = true;
  emit('error');
};

const attachment = computed(() => attachments.value[0]);

const isReel = computed(
  () => attachment.value.fileType === ATTACHMENT_TYPES.IG_REEL
);
</script>

<template>
  <BaseBubble
    class="max-w-[20rem] overflow-hidden p-1.5"
    data-bubble-name="video"
    @click="showGallery = Boolean(attachment.dataUrl) && !hasError"
  >
    <div class="relative group rounded-lg overflow-hidden">
      <div
        v-if="isReel"
        class="absolute p-2 flex items-start justify-end right-0 pointer-events-none"
      >
        <Icon icon="i-lucide-instagram" class="text-white shadow-lg" />
      </div>
      <video
        v-if="attachment.dataUrl && !hasError"
        controls
        class="max-h-[22rem] max-w-full rounded-lg bg-black object-contain skip-context-menu"
        :src="attachment.dataUrl"
        :class="{
          'w-48': isReel,
          'w-80': !isReel,
        }"
        @click.stop
        @error="handleError"
      />
      <div
        v-else
        class="flex w-80 max-w-full items-center gap-2 p-5 text-sm text-n-slate-11"
      >
        <Icon icon="i-lucide-circle-off" />
        {{ t('GALLERY_VIEW.MEDIA_UNAVAILABLE') }}
      </div>
      <Button
        v-if="attachment.dataUrl && !hasError"
        :aria-label="t('GALLERY_VIEW.EXPAND')"
        :title="t('GALLERY_VIEW.EXPAND')"
        icon="i-lucide-expand"
        slate
        solid
        sm
        class="absolute right-2 top-2 opacity-80"
        @click.stop="showGallery = true"
      />
    </div>
  </BaseBubble>
  <GalleryView
    v-if="showGallery"
    v-model:show="showGallery"
    :attachment="useSnakeCase(attachment)"
    :all-attachments="filteredCurrentChatAttachments"
    :conversation-id="conversationId"
    @forward="forwardMediaMessage"
    @error="handleError"
    @close="() => (showGallery = false)"
  />
</template>
