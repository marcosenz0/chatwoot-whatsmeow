<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import Icon from 'next/icon/Icon.vue';

const props = defineProps({
  adContext: {
    type: Object,
    required: true,
  },
});

const { t } = useI18n();
const imageFailed = ref(false);

const valueFor = (camelKey, snakeKey) =>
  props.adContext?.[camelKey] ?? props.adContext?.[snakeKey];

const safeHttpUrl = value => {
  const url = String(value || '').trim();
  return /^https?:\/\//i.test(url) ? url : '';
};

const safePreviewUrl = value => {
  const url = String(value || '').trim();
  if (/^data:image\/(?:png|jpe?g|gif|webp);base64,[a-z0-9+/=]+$/i.test(url)) {
    return url;
  }

  return safeHttpUrl(url);
};

const mediaType = computed(() =>
  String(valueFor('mediaType', 'media_type') || '').toLowerCase()
);
const previewImageUrl = computed(() => {
  if (imageFailed.value) return '';

  const thumbnail =
    valueFor('thumbnailDataUrl', 'thumbnail_data_url') ||
    valueFor('thumbnailUrl', 'thumbnail_url') ||
    valueFor('originalImageUrl', 'original_image_url');
  if (thumbnail) return safePreviewUrl(thumbnail);

  return mediaType.value === 'image'
    ? safePreviewUrl(valueFor('mediaUrl', 'media_url'))
    : '';
});
const adLink = computed(
  () =>
    safeHttpUrl(valueFor('adPreviewUrl', 'ad_preview_url')) ||
    safeHttpUrl(valueFor('sourceUrl', 'source_url')) ||
    safeHttpUrl(valueFor('wtwaWebsiteUrl', 'wtwa_website_url'))
);
const title = computed(
  () => valueFor('title', 'title') || t('CONVERSATION.WHATSMEOW_AD.TITLE')
);
const description = computed(
  () =>
    valueFor('body', 'body') ||
    valueFor('greetingMessageBody', 'greeting_message_body') ||
    ''
);
const sourceApp = computed(() => {
  const source = String(valueFor('sourceApp', 'source_app') || '').trim();
  if (!source) return '';

  return source.charAt(0).toUpperCase() + source.slice(1).toLowerCase();
});
const isVideo = computed(() => mediaType.value === 'video');
</script>

<template>
  <div
    class="mb-2 overflow-hidden rounded-lg border border-n-weak bg-n-alpha-black1"
  >
    <div class="flex items-center gap-2 border-b border-n-weak px-2.5 py-2">
      <span
        class="flex size-5 shrink-0 items-center justify-center rounded-full bg-n-brand/15 text-n-brand"
      >
        <Icon icon="i-lucide-megaphone" class="size-3" />
      </span>
      <span class="min-w-0 flex-1 text-xs font-semibold text-n-slate-12">
        {{ t('CONVERSATION.WHATSMEOW_AD.LEAD') }}
      </span>
      <span v-if="sourceApp" class="truncate text-[11px] text-n-slate-10">
        {{ sourceApp }}
      </span>
    </div>

    <div class="flex min-w-0 items-center gap-2.5 p-2.5">
      <span
        class="relative flex size-12 shrink-0 items-center justify-center overflow-hidden rounded-md bg-n-alpha-2 text-n-slate-10"
      >
        <img
          v-if="previewImageUrl"
          :src="previewImageUrl"
          alt=""
          class="size-full object-cover"
          @error="imageFailed = true"
        />
        <Icon
          v-else
          :icon="isVideo ? 'i-lucide-video' : 'i-lucide-image'"
          class="size-5"
        />
        <span
          v-if="isVideo && previewImageUrl"
          class="absolute inset-0 flex items-center justify-center bg-black/25"
        >
          <Icon icon="i-lucide-play" class="size-4 fill-white text-white" />
        </span>
      </span>

      <span class="min-w-0 flex-1">
        <span class="block truncate text-xs font-semibold text-n-slate-12">
          {{ title }}
        </span>
        <span
          v-if="description"
          class="mt-0.5 block line-clamp-2 text-xs leading-4 text-n-slate-11"
        >
          {{ description }}
        </span>
      </span>

      <a
        v-if="adLink"
        :href="adLink"
        target="_blank"
        rel="noreferrer noopener nofollow"
        class="flex shrink-0 items-center gap-1 rounded-md px-1.5 py-1 text-[11px] font-medium text-n-brand hover:bg-n-alpha-black2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand"
      >
        {{ t('CONVERSATION.WHATSMEOW_AD.VIEW') }}
        <Icon icon="i-lucide-external-link" class="size-3" />
      </a>
    </div>
  </div>
</template>
