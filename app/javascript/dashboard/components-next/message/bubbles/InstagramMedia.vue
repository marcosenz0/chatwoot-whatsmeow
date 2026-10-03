<script setup>
import { computed, ref } from 'vue';
import { useSnakeCase } from 'dashboard/composables/useTransformKeys';
import GalleryView from 'dashboard/components/widgets/conversation/components/GalleryView.vue';
import InstagramPreview from '../InstagramPreview.vue';
import BaseBubble from './Base.vue';
import { useMessageContext } from '../provider.js';

const {
  attachments,
  filteredCurrentChatAttachments,
  conversationId,
  id,
  instagramPreview,
  showInstagramLink,
} = useMessageContext();
const showGallery = ref(false);
const selectedPost = ref(null);
const attachment = computed(
  () =>
    attachments.value[0] || {
      id: `instagram-${id.value}`,
      messageId: id.value,
      fileType: 'share',
      dataUrl: instagramPreview.value.permalink,
    }
);
const galleryAttachment = computed(() =>
  selectedPost.value
    ? {
        id: `instagram-post-${id.value}`,
        message_id: id.value,
        file_type: 'image',
        data_url: selectedPost.value.image_url,
        instagram_url: selectedPost.value.url,
      }
    : {
        ...useSnakeCase(attachment.value),
        message_id: id.value,
      }
);
const galleryAttachments = computed(() =>
  attachments.value.length && !selectedPost.value
    ? filteredCurrentChatAttachments.value
    : [galleryAttachment.value]
);
const expand = post => {
  selectedPost.value = post || null;
  showGallery.value = true;
};
</script>

<template>
  <BaseBubble
    class="max-w-[21rem] overflow-hidden p-1.5"
    data-bubble-name="instagram-media"
  >
    <a
      v-if="showInstagramLink"
      :href="instagramPreview.permalink"
      target="_blank"
      rel="noopener noreferrer"
      class="block break-all p-3 text-sm text-n-blue-text underline"
    >
      {{ instagramPreview.permalink }}
    </a>
    <InstagramPreview
      v-else-if="!showGallery"
      :url="instagramPreview.permalink"
      :conversation-id="conversationId"
      :message-id="id"
      @expand="expand"
    />
  </BaseBubble>
  <GalleryView
    v-if="showGallery"
    v-model:show="showGallery"
    :attachment="galleryAttachment"
    :all-attachments="galleryAttachments"
    :conversation-id="conversationId"
    @close="showGallery = false"
  />
</template>
