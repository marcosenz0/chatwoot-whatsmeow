<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useSnakeCase } from 'dashboard/composables/useTransformKeys';
import { getInstagramMediaUrl } from 'dashboard/helper/instagramMediaHelper';
import GalleryView from 'dashboard/components/widgets/conversation/components/GalleryView.vue';
import Icon from 'next/icon/Icon.vue';
import BaseBubble from './Base.vue';
import { useMessageContext } from '../provider.js';

const { t } = useI18n();
const { attachments, filteredCurrentChatAttachments, conversationId } =
  useMessageContext();
const showGallery = ref(false);
const attachment = computed(() => attachments.value[0]);
const media = computed(() => getInstagramMediaUrl(attachment.value.dataUrl));
</script>

<template>
  <BaseBubble
    class="max-w-[21rem] overflow-hidden p-1.5"
    data-bubble-name="instagram-media"
  >
    <div
      class="relative h-[26rem] w-80 max-w-full overflow-hidden rounded-lg bg-white"
    >
      <iframe
        v-if="!showGallery"
        :src="media.embedUrl"
        :title="t('GALLERY_VIEW.INSTAGRAM_PREVIEW')"
        class="pointer-events-none h-full w-full border-0"
        loading="lazy"
        tabindex="-1"
        aria-hidden="true"
      />
      <button
        type="button"
        :aria-label="t('GALLERY_VIEW.EXPAND')"
        class="absolute inset-0 flex items-end justify-end bg-gradient-to-t from-black/30 via-transparent to-transparent p-3 hover:from-black/50 focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-n-brand"
        @click="showGallery = true"
      >
        <span
          class="flex items-center gap-2 rounded-lg bg-black/70 px-3 py-2 text-sm text-white"
        >
          <Icon icon="i-lucide-expand" />
          {{ t('GALLERY_VIEW.EXPAND') }}
        </span>
      </button>
    </div>
    <a
      :href="media.permalink"
      target="_blank"
      rel="noopener noreferrer"
      class="mt-2 block px-2 text-xs text-n-blue-text"
    >
      {{ t('GALLERY_VIEW.OPEN_INSTAGRAM') }}
    </a>
  </BaseBubble>
  <GalleryView
    v-if="showGallery"
    v-model:show="showGallery"
    :attachment="useSnakeCase(attachment)"
    :all-attachments="filteredCurrentChatAttachments"
    :conversation-id="conversationId"
    @close="showGallery = false"
  />
</template>
